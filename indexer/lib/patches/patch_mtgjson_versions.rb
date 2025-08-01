# Cleanup differences between mtgjson v3 / v4 / v5

# This patch ended up as dumping ground for far too much random stuff

class PatchMtgjsonVersions < Patch
  # This can go away once mtgjson fixes their bugs
  def calculate_cmc(mana_cost)
    mana_cost.split(/[\{\}]+/).reject(&:empty?).map{|c|
      case c
      when /\A[WUBRGCS]\z/, /\A[WUBRG]\/[WUBRGP]\z/
        1
      when "X", "Y", "Z"
        0
      when "HW"
        0.5
      when /\d+/
        c.to_i
      else
        warn "Cannot calculate cmc of #{c} mana symbol"
        0
      end
    }.sum
  end

  def get_cmc(card)
    cmc = [card.delete("convertedManaCost"), card.delete("cmc")].compact.first
    fcmc = card.delete("faceConvertedManaCost")

    # mtgjson bug
    # https://github.com/mtgjson/mtgjson/issues/818
    if card["layout"] == "modal_dfc" or card["layout"] == "reversible_card"
      return calculate_cmc(card["manaCost"] || "")
    end

    if fcmc
      case card["layout"]
      when "split", "aftermath", "adventure"
        cmc = fcmc
      when "transform"
        # ignore because
        # https://github.com/mtgjson/mtgjson/issues/294
      else
        if cmc != fcmc
          warn "#{card["layout"]} #{card["name"]} has fcmc #{fcmc} != cmc #{cmc}"
        end
      end
    end

    cmc = cmc.to_i if cmc.to_i == cmc
    cmc
  end

  def assign_number(card)
    @seen ||= {}
    set_code = card["set"]["official_code"]
    base_number = card["number"]
    counter = "a"
    while @seen[[set_code, base_number, counter]]
      counter.succ!
    end
    @seen[[set_code, base_number, counter]] = true
    card["promoTypes"] ||= []
    case counter
    when "a"
      card["promoTypes"] << "reversiblefront"
    when "b"
      card["promoTypes"] << "reversibleback"
    else
      warn "More than two parts of same reversible card #{set_code} #{base_number}"
    end
    card["number"] = "#{base_number}#{counter}"
  end

  def call
    # Fix Alchemy cards names into something search engine can work with
    # mtgjson "A-Akki Ronin" turns into "Akki Ronin (Alchemy)"
    each_printing do |card|
      next unless card.delete("isRebalanced")
      card["alchemy"] = true
      card["name"] = alchemy_name_fix(card["name"])
      card["faceName"] = alchemy_name_fix(card["faceName"])
    end

    each_printing do |card|
      if card["faceName"] and card["name"].include?("//")
        card["names"] = card["name"].split(" // ")
        card["name"] = card.delete("faceName")
      end
    end

    each_printing do |card|
      card["cmc"] = get_cmc(card)

      # Reversible cards are totally ridiculous, and mtgjson shouldn't be pretending it's a single damn card.
      # With SLD it was at least 2 faces we could split but TDM has ridiculous 4-faced cards.
      # These are two separate cards as far as game rules are concerned
      if card["layout"] == "reversible_card"
        case card["set"]["official_code"]
        when "SLD", "REX"
          # These are at least easily fixable
          card["layout"] = "normal"
          card.delete "names"
          assign_number(card)
        when "TDM"
          case card["name"]
          when "Clarion Conqueror", "Magmatic Hellkite", "Ugin, Eye of the Storms"
            # These are at least easily fixable
            card["layout"] = "normal"
            card.delete "names"
            assign_number(card)
          when "Marang River Regent"
            card["layout"] = "adventure"
            card["names"] = ["Marang River Regent", "Coil and Catch"]
            assign_number(card)
          when "Coil and Catch"
            card["layout"] = "adventure"
            card["names"] = ["Marang River Regent", "Coil and Catch"]
            assign_number(card)
            card.delete "power"
            card.delete "toughness"
            card.delete "keywords"
            # it has typo in remainder text in mtgjson
            card["text"] = "Draw three cards, then discard a card. (Then shuffle this card into its owner's library.)"
          when "Scavenger Regent"
            card["layout"] = "adventure"
            card["names"] = ["Scavenger Regent", "Exude Toxin"]
            assign_number(card)
          when "Exude Toxin"
            card["layout"] = "adventure"
            card["names"] = ["Scavenger Regent", "Exude Toxin"]
            assign_number(card)
            card.delete "power"
            card.delete "toughness"
            card.delete "keywords"
            card["text"] = "Each non-Dragon creature gets -X/-X until end of turn. (Then shuffle this card into its owner's library.)"
          when "Bloomvine Regent"
            card["layout"] = "adventure"
            card["names"] = ["Bloomvine Regent", "Claim Territory"]
            assign_number(card)
          when "Claim Territory"
            card["layout"] = "adventure"
            card["names"] = ["Bloomvine Regent", "Claim Territory"]
            assign_number(card)
            card.delete "power"
            card.delete "toughness"
            card.delete "keywords"
            card["text"] = "Search your library for up to two basic Forest cards, reveal them, put one onto the battlefield tapped and the other into your hand, then shuffle. (Also shuffle this card.)"
          else
            warn "Can't handle reversible card #{card["name"]} #{card["names"]} #{card["set"]["official_code"]} #{card["number"]}"
          end
        else
          warn "Can't handle reversible card #{card["name"]} #{card["names"]} #{card["set"]["official_code"]} #{card["number"]}"
        end
      end

      # This is text because of some X planeswalkers
      # It's more convenient for us to mix types
      card["loyalty"] = card["loyalty"].to_i if card["loyalty"] and card["loyalty"] =~ /\A\d+\z/

      # That got renamed a few times as DFCs are now of 3 types (transform, meld, mdfc)
      card["layout"] = "transform" if card["layout"] == "double-faced"

      card["mana"] = card.delete("manaCost")&.downcase

      # v4 uses []/"" while v3 just dropped such fields
      card.delete("supertypes") if card["supertypes"] == []
      card.delete("subtypes") if card["subtypes"] == []
      card.delete("rulings") if card["rulings"] == []
      card.delete("text") if card["text"] == ""
      card.delete("names") if card["names"] == []

      if card["flavorText"]
        card["flavor"] = card.delete("flavorText")
      end

      if card["borderColor"]
        card["border"] = card.delete("borderColor")
      end

      if card["frameEffects"]
        card["frame_effects"] = card.delete("frameEffects")
      elsif card["frameEffect"]
        card["frame_effects"] = [card.delete("frameEffect")]
      end

      # This conflicts with isTextless in annoying ways
      if card["frame_effects"]
        card["frame_effects"].delete("textless")
      end

      # It's randomly added to Mount Doom, likely as a mistake
      if card["frame_effects"]
        card["frame_effects"].delete("boosterfun")
      end

      # This is not quite set-based as there are Arena-specific fixed art cards
      # We used to have set-based logic, but it has no way of finding cards like znr/288†b
      card["digital"] = card.delete("isOnlineOnly")
      card["fullart"] = card.delete("isFullArt")
      card["oversized"] = card.delete("isOversized")
      # not sure what to do with it, isPromo flag, promoTypes, and our is:promo logic are all very different
      # so for now this is not used
      card["promo"] = card.delete("isPromo")
      card["spotlight"] = card.delete("isStorySpotlight")
      card["textless"] = card.delete("isTextless")
      card["timeshifted"] = card.delete("isTimeshifted")

      # OC21/OAFC are technically "display cards" not oversized
      # https://github.com/mtgjson/mtgjson/issues/815
      # O90P and OLEP are just mtgjson bug
      if %W[OC21 OAFC O90P OLEP].include?(card["set"]["official_code"])
        card["oversized"] = true
      end

      # mtgjson bug
      if card["set"]["official_code"] == "MOC" and (card["types"].include?("Plane") or card["types"].include?("Phenomenon"))
        card["oversized"] = true
      end

      # Moved in v5
      card["arena"] = true if card.delete("isArena") or card["availability"]&.delete("arena")
      card["paper"] = true if card.delete("isPaper") or card["availability"]&.delete("paper")
      card["mtgo"] = true if card.delete("isMtgo") or card["availability"]&.delete("mtgo")
      # shandalar data is incorrect in mtgjson, so we do not want it, we do our own calculations
      # dreamcast data is incorrect in mtgjson, there's no replacement on our side

      # This logic changed at some point, I like old logic better
      if card["oversized"] or %W[CEI CED 30A].include?(card["set"]["official_code"]) or card["border"] == "gold"
        card["nontournament"] = true
        card.delete("arena")
        card.delete("paper")
        card.delete("mtgo")
      end

      # Drop v3 layouts, use v4 layout here
      if card["layout"] == "plane" or card["layout"] == "phenomenon"
        card["layout"] = "planar"
      end

      if card["layout"] == "modal_dfc"
        card["layout"] = "modaldfc"
      end

      # Renamed in v4, then moved in v5. v5 makes it a String
      card["multiverseid"] ||= card.delete("multiverseId")
      card["multiverseid"] ||= card["identifiers"]&.delete("multiverseId")
      card["multiverseid"] = card["multiverseid"].to_i if card["multiverseid"].is_a?(String) and card["multiverseid"] =~ /\A\d+\z/

      if card.has_key?("isReserved")
        if card.delete("isReserved")
          card["reserved"] = true
        end
      end

      if card["promoTypes"]
        card["promo_types"] = card["promoTypes"]
      end

      card["stamp"] = card.delete("securityStamp")

      if card["attractionLights"]
        card["attraction_lights"] = card["attractionLights"]
      end

      # Unicode vs ASCII
      if card["rulings"]
        card["rulings"].each do |ruling|
          ruling["text"] = cleanup_unicode_punctuation(ruling["text"])
        end
      end
      if card["text"]
        card["text"] = cleanup_unicode_punctuation(card["text"])
      end
      if card["artist"]
        card["artist"] = cleanup_unicode_punctuation(card["artist"])
      end

      # Flavor text quick fix because v4 doesn't have newlines
      if card["flavor"]
        card["flavor"] = card["flavor"].gsub(%[" —], %["\n—]).gsub(%[" "], %["\n"])
      end

      # mtgjson started using * to indicate italics? annoying
      if card["flavor"]
        card["flavor"] = card["flavor"].delete("*")
      end

      if card["flavorName"]
        card["flavor_name"] = card.delete("faceFlavorName") || card.delete("flavorName")
      end

      if card["rulings"]
        rulings_dates = card["rulings"].map{|x| x["date"] }
        unless rulings_dates.sort == rulings_dates
          warn "Rulings for #{card["name"]} in #{card["set"]["name"]} not in order"
        end
      end

      if card["keywords"]
        card["keywords"] = card["keywords"].map(&:downcase)
      end

      # Numbering conflict in mtgjson data
      # They have RZ15 (which we turn into RZ15a/RZ15b) and RZ15b
      # We need to move that RZ15b away to something else
      # And same shit for CU12a, CU12b
      if card["set"]["official_code"] == "UNK"
        if card["number"] == "RZ15b" and
          card["number"] = "RZ15x"
        end
        if card["number"] == "CU12a" and
          card["number"] = "CU12x"
        end
        if card["number"] == "CU12b" and
          card["number"] = "CU12y"
        end
      end

      # At least for now:
      # "123a" but "U123"
      if card["number"]
        card["number"] = card["number"].sub(/(\D+)\z/){ $1.downcase }
      end

      # Weird Escape formatting, make it match other similar abilities
      if card["text"] =~ /^Escape—/
        card["text"] = card["text"].gsub(/^Escape—/, "Escape — ")
      end

      card.delete("language") if card["language"] == "English"

      if card["finishes"]&.include?("etched")
        card["etched"] = true
      end

      # First https://github.com/mtgjson/mtgjson/issues/1094 but it keeps coming back
      # so a permanent fix here
      if card["subtypes"]&.include?("Saga") and card["layout"] == "normal"
        card["layout"] = "saga"
      end

      # First https://github.com/mtgjson/mtgjson/issues/1094 but it keeps coming back
      # so a permanent fix here
      if card["frame_effects"]&.include?("borderless")
        card["border"] = "borderless"
        card["frame_effects"].delete("borderless")
      end

      # Some cmb1/cmb2 cards not updated yet
      if card["types"].include?("Tribal")
        card["types"] = card["types"].map{|t| t == "Tribal" ? "Kindred" : t}
      end

      # redundant with other fields, just predelete
      card.delete("type")

      # mtgjson bug, ydmu is correct, mb2 is not
      if card["name"] == "Oracle of the Alpha"
        card["spellbook"] = ["Ancestral Recall", "Black Lotus", "Mox Emerald", "Mox Jet", "Mox Pearl", "Mox Ruby", "Mox Sapphire", "Time Walk", "Timetwister"]
      end
    end

    # It's a reversible token not a card, so it shouldn't be in card data
    delete_printing_if do |card|
      card["name"] == "Mechtitan"
    end

    # spoiler set with some bad cards, remove this before release
    delete_printing_if do |card|
      # if card["name"] == "Claim Territory"
      #   pp card.except("set", "identifiers", "purchaseUrls")
      # end
      card["setCode"] == "TDM" and card["layout"] == "reversible_card"
    end
  end

  def cleanup_unicode_punctuation(text)
    text.tr(%[‘’“”], %[''""])
  end

  def alchemy_name_fix(name)
    return unless name
    name.split(" // ").map{|s|
      if s =~ /\AA-(.*)/
        "#{$1} (Alchemy)"
      else
        s
      end
    }.join(" // ")
  end
end
