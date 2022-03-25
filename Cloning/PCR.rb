needs "Standard Libs/Debug Lib"
needs "Cloning Libs/Cloning"
class Protocol
    include Debug
    include Cloning
    # I/O
    FWD = "Forward Primer"
    REV = "Reverse Primer"
    TEMPLATE = "Template"
    FRAGMENT = "PCR Product"
    
    REACTION_VOLUME = 50.0
    TOTAL_THERMOCYCLERS = 1
    ANNEAL_TEMP_TOLERANCE = 1.0 # Reactions where the difference in annealing temp is less than this value may be run together
    
    BLOCKS_PER_THERMOCYCLER = 3
    ZONES_PER_BLOCK = 2
    REACTIONS_PER_ZONE = 16
    
    def main
        current_taken_items = []
        # Remember to add volume information to input and output object types (and concentration data where applicable).
        # Two different input volumes to avoid pipetting .5 ul of Q5 when only 1 operation in batch
        if operations.count == 1
            input_volumes = {FWD => (REACTION_VOLUME / 50.0).round(2), REV => (REACTION_VOLUME / 50.0).round(2), TEMPLATE => (REACTION_VOLUME / 50.0).round(2), "Buffer" => (REACTION_VOLUME*0.33).round(2), "dntp" => (REACTION_VOLUME*0.022).round(2), "Q5" => (REACTION_VOLUME*0.022).round(2)}
        else
            input_volumes = {FWD => (REACTION_VOLUME / 50.0).round(2), REV => (REACTION_VOLUME / 50.0).round(2), TEMPLATE => (REACTION_VOLUME / 50.0).round(2), "Buffer" => (REACTION_VOLUME*0.22).round(2), "dntp" => (REACTION_VOLUME*0.022).round(2), "Q5" => (REACTION_VOLUME*0.011).round(2)}
        end
        output_volumes = {FRAGMENT => (REACTION_VOLUME*0.95 - 2.0).round}
        
        operations.running.add_static_inputs "Q5", "Q5 HF DNA Polymerase", "Enzyme Stock"
        operations.running.add_static_inputs "Buffer", "Q5 Reaction Buffer", "Enzyme Buffer Stock"
        operations.running.add_static_inputs "dntp", "10mM dNTP", "Screw Cap Tube Stock"
        check_user_inputs [FWD, REV, TEMPLATE], input_volumes, current_taken_items
        assign_input_items ["Buffer", "dntp", "Q5"], input_volumes, current_taken_items
        return {} if check_for_errors
        robust_make [FRAGMENT], current_taken_items
        
        operations.each do |op|
            t1 = op.input(FWD).sample.properties["T Anneal"]
            t2 = op.input(REV).sample.properties["T Anneal"]
            op.temporary[:tanneal] = [t1, t2].min
        end
        operations.sort_by! {|op| op.temporary[:tanneal]}

        ##  Ops can occupy the same zone if they are within 1C of lowest annealing op in the zone AND the
        ##  zone is occupied by < 16 ops already. Also, two zones in the same block cannot be more than
        ##  5C apart (limitation of veriflex function on PCR machine).

        op_array = Array.new(TOTAL_THERMOCYCLERS*BLOCKS_PER_THERMOCYCLER) {Array.new(ZONES_PER_BLOCK) {Array.new}}
        block = 0
        zone_in_block = 0
        reaction_in_zone = 0
        zone_tanneal = 0
        operations.running.each_with_index do |op, i|
            if i == 0
                zone_tanneal = op.temporary[:tanneal]
            elsif (reaction_in_zone >= REACTIONS_PER_ZONE) || (op.temporary[:tanneal] - zone_tanneal > ANNEAL_TEMP_TOLERANCE) #new zone
                zone_in_block += 1
                reaction_in_zone = 0
                if (zone_in_block >= ZONES_PER_BLOCK) || (op.temporary[:tanneal] - zone_tanneal > 5.0)#new block
                    block += 1
                    zone_in_block = 0
                end
                zone_tanneal = op.temporary[:tanneal]
            end
            if not op_array[block].blank? #prevents scheduling of more blocks than total capacity of the lab
                op_array[block][zone_in_block] << op
            else
                show do
                    title "Number of reactions scheduled exceeds total thermocycler capacity of lab."
                    note "Number of reactions scheduled exceeds total thermocycler capacity of lab."
                    warning "Aborting protocol. Please check with the lab manager for further instructions."
                end
                return {}
            end
            reaction_in_zone += 1
        end
        blocks_required = block + 1
        op_array.map! {|block| block.reject {|zone| zone.empty?}}
        op_array.reject! {|block| block.empty?}
        op_array.compact!
    
        data = show do
            title "Check if enough blocks are available"
            warning "Warning: Selecting \"No\" will abort the protocol."
            select [ "Yes", "No"], var: "choice", label: "Are there at least #{blocks_required} blocks currently available on the pcr machine?", default: 0
        end

        if data[:choice] == "No"
            show do
                title "Number of reactions scheduled exceeds available capacity."
                note "Number of reactions scheduled exceeds available capacity."
                warning "Aborting protocol. Please check with the lab manager for further instructions."
            end
            return {}
        end

        show do
            title "Keep all items on ice"
            warning "Note: All items used in this protocol should be kept on ice (or thawed at room temperature then immediately transfered to ice)."
        end
        
        #creating master mixes
        mm_buffer_vol_by_item = {}
        dp_buffer_vol_by_item = {}
        mm_dntp_vol_by_item = {}
        dp_q5_vol_by_item = {}
        if operations.running.count == 1 #special case to prevent pipetting .5 ul of q5
            mm_to_make = ((REACTION_VOLUME-input_volumes[FWD]-input_volumes[REV]-input_volumes[TEMPLATE])/2.0)*1.1
            dp_to_make = (REACTION_VOLUME-input_volumes[FWD]-input_volumes[REV]-input_volumes[TEMPLATE])*1.1
            water_for_mm = (mm_to_make - operations.running.count*input_volumes["Buffer"] / 3.0 - operations.running.count*input_volumes["dntp"]).round(2)
            water_for_dp = (dp_to_make - (2.0*input_volumes["Buffer"] / 3.0) - input_volumes["Q5"]).round(2)
            mm_buffer_vol_by_item = {operations.running[0].input("Buffer").item => input_volumes["Buffer"]/3.0}
            dp_buffer_vol_by_item = {operations.running[0].input("Buffer").item => 2.0*input_volumes["Buffer"]/3.0}
        else
            mm_to_make = operations.running.count*((REACTION_VOLUME-input_volumes[FWD]-input_volumes[REV]-input_volumes[TEMPLATE])/2.0)*1.1
            dp_to_make = operations.running.count*((REACTION_VOLUME-input_volumes[FWD]-input_volumes[REV]-input_volumes[TEMPLATE])/2.0)*1.1
            water_for_mm = (mm_to_make - operations.running.count*input_volumes["Buffer"] / 2.0 - operations.running.count*input_volumes["dntp"]).round(2)
            water_for_dp = (dp_to_make - operations.running.count*input_volumes["Buffer"] / 2.0 - operations.running.count*input_volumes["Q5"]).round(2)
            operations.running.each do |op|
                if mm_buffer_vol_by_item.keys.include? op.input("Buffer").item
                    mm_buffer_vol_by_item[op.input("Buffer").item] += input_volumes["Buffer"]/2.0
                else
                    mm_buffer_vol_by_item[op.input("Buffer").item] = input_volumes["Buffer"]/2.0
                end
                if dp_buffer_vol_by_item.keys.include? op.input("Buffer").item
                    dp_buffer_vol_by_item[op.input("Buffer").item] += input_volumes["Buffer"]/2.0
                else
                    dp_buffer_vol_by_item[op.input("Buffer").item] = input_volumes["Buffer"]/2.0
                end
            end
        end
        operations.running.each do |op|
            if mm_dntp_vol_by_item.keys.include? op.input("dntp").item
                mm_dntp_vol_by_item[op.input("dntp").item] += input_volumes["dntp"]
            else
                mm_dntp_vol_by_item[op.input("dntp").item] = input_volumes["dntp"]
            end
            if dp_q5_vol_by_item.keys.include? op.input("Q5").item
                dp_q5_vol_by_item[op.input("Q5").item] += input_volumes["Q5"]
            else
                dp_q5_vol_by_item[op.input("Q5").item] = input_volumes["Q5"]
            end
        end
        
        
        ot2_choice = show do
            title "Select execution method"
            select ["No", "Yes"], var: "ot2", label: "Is the OT2 robot available?"
        end
        
        if ot2_choice[:ot2] == "Yes"

            prot = OTAqProtocol.new
            
            prot.add_labware_definition('24-well-1.5ml-rack')
    
            water_container = prot.labware.load('point', '1', 'Water')
            water = prot.dummy_item "DI Water"
            prot.assign_wells [water], [water_container.wells(0)]
            
            td = prot.modules.load('tempdeck', '10')
            temp_deck_tubes = prot.labware.load('PCR-strip-tall', '10', 'Temp deck w/ PCR tubes')
            
            # p10 = prot.instruments.P10_Single(mount: 'right', tip_model: "tiprack-10ul")
            tip_racks_small = []
            tip_racks_small << prot.labware.load('tiprack-10ul', '3')
            tip_racks_small << prot.labware.load('tiprack-10ul', '6')
            tip_racks_large = [prot.labware.load('tiprack-200ul', '9')]
            p10 = prot.instruments.P10_Single(mount: 'right', tip_racks: tip_racks_small)
            p300 = prot.instruments.P300_Single(mount: 'left', tip_racks: tip_racks_large)
            
            prot.assign_wells operations.running.map{|op| op.output(FRAGMENT).item}, temp_deck_tubes.wells[0..operations.running.count-1]
            operations.running.map{|op| op.temporary[:aliquot_tube] = prot.dummy_item "Empty Tube"}
            prot.assign_wells(operations.running.map{|op| op.temporary[:aliquot_tube]}, temp_deck_tubes.wells[operations.running.count..(operations.running.count * 2 - 1)])
            
            prot.assign_wells operations.running.map{|op| op.input("Q5").item}.uniq
            prot.assign_wells operations.running.map{|op| op.input("dntp").item}.uniq
            prot.assign_wells operations.running.map{|op| op.input("Buffer").item}.uniq
            prot.assign_wells operations.running.map{|op| op.input(FWD).item}.uniq
            prot.assign_wells operations.running.map{|op| op.input(REV).item}.uniq
            prot.assign_wells operations.running.map{|op| op.input(TEMPLATE).item}.uniq
            
            td.set_temperature(4)
            
            p300.pick_up_tip
            operations.running.each do |op|
                p300.aspirate(49, prot.find_well(water))
                p300.dispense(49, prot.find_well(op.temporary[:aliquot_tube]).bottom(0))
            end
            p300.drop_tip
            
            operations.running.each do |op|
                p10.pick_up_tip
                p10.aspirate 1, prot.find_well(op.input(TEMPLATE).bottom(0))
                p10.dispense 1, prot.find_well(op.temporary[:aliquot_tube])
                3.times do
                    p10.aspirate 10, prot.find_well(op.input(TEMPLATE).bottom(0))
                    p10.dispense 10, prot.find_well(op.temporary[:aliquot_tube])
                end
                p10.drop_tip
            end
            
            # show do
            #     title "Combine water, buffer, and dNTPs"
            #     check "Label a 1.5 ml epindorf tube \"MM\" and place it on ice"
            #     check "Add reagents to \"MM\" according to the following chart:"
            #     table_matrix = Array.new {Array.new}
            #     table_matrix[0] = ["Water to add", "Buffer to add", "dNTP to add"]
            #     table_matrix[1] = [{content: water_for_mm.to_s, check: true} , Array.new, Array.new]
            #     mm_buffer_vol_by_item.each{|item, vol| table_matrix[1][1] << "#{vol.round(2)} µl of #{item.id}"}
            #     mm_dntp_vol_by_item.each{|item, vol| table_matrix[1][2] << "#{vol.round(2)} µl of #{item.id}"}
            #     table_matrix[1][1] = {content: table_matrix[1][1].join(", "), check: true}
            #     table_matrix[1][2] = {content: table_matrix[1][2].join(", "), check: true}
            #     table table_matrix
            # end
            
            
            
            p10.pick_up_tip
            operations.running.each do |op|
                p10.aspirate(input_volumes["Buffer"], prot.find_well(op.input("Buffer").item).bottom(0))
                p10.dispense(input_volumes["Buffer"], prot.find_well(op.output("MoClo Reaction Product").item).bottom(0))
                p10.aspirate(input_volumes["Buffer"], prot.find_well(op.output("MoClo Reaction Product").item).bottom(0))
                p10.dispense(input_volumes["Buffer"], prot.find_well(op.output("MoClo Reaction Product").item).bottom(0))
            end
            p10.drop_tip
            
            # Add other reagents
            operations.running.each do |op|
                p10.pick_up_tip
                p10.aspirate(input_volumes["Vector"], prot.find_well(op.input("Vector").item).bottom(0))
                p10.dispense(input_volumes["Vector"], prot.find_well(op.output("MoClo Reaction Product").item).bottom(0))
                p10.drop_tip
                
                op.input_array("Insert").items.each do |insert_item|
                    p10.pick_up_tip
                    p10.aspirate(input_volumes["Insert"], prot.find_well(insert_item).bottom(0))
                    p10.dispense(input_volumes["Insert"], prot.find_well(op.output("MoClo Reaction Product").item).bottom(0))
                    p10.drop_tip
                end
                
                p10.pick_up_tip
                p10.aspirate(input_volumes["Ligase"], prot.find_well(op.input("Ligase").item).bottom(0))
                p10.dispense(input_volumes["Ligase"], prot.find_well(op.output("MoClo Reaction Product").item).bottom(0))
                # Small mix to ensure ligase is added.
                p10.aspirate(5, prot.find_well(op.output("MoClo Reaction Product").item).bottom(0))
                p10.dispense(5, prot.find_well(op.output("MoClo Reaction Product").item).bottom(0))
                p10.drop_tip
                
                p10.pick_up_tip
                p10.aspirate(input_volumes["MoClo Restriction Enzyme"], prot.find_well(op.input("MoClo Restriction Enzyme").item).bottom(0))
                p10.dispense(input_volumes["MoClo Restriction Enzyme"], prot.find_well(op.output("MoClo Reaction Product").item).bottom(0))
                # Final mix
                3.times do
                    p10.aspirate(10, prot.find_well(op.output("MoClo Reaction Product").item).bottom(0))
                    p10.dispense(10, prot.find_well(op.output("MoClo Reaction Product").item).bottom(0))
                end
                p10.drop_tip
            end
            
            td.wait_for_temp
            p10.delay(7200)
            
            td.set_temperature(50)
            p10.delay(400)
            
            td.set_temperature(80)
            p10.delay(600)
            
            td.set_temperature(4)
            
            robust_take_inputs [TEMPLATE, FWD, REV, "Buffer", "dntp", "Q5"], current_taken_items, interactive: true, method: "boxes"
            
            show do
                title "Prepare output PCR tubes."
                note "Get out #{operations.running.count} new PCR tubes and label with the following IDs: #{operations.running.map {|op| op.output("MoClo Reaction Product").item.id}.to_sentence}"
            end
            
            run_protocol prot
            
            show do
               title "Set timer for removing inputs"
               check "Set a timer for 20 min, after which the robot should be done pipetting and you can remove and store input items (see following slide)."
               timer initial: { hours: 0, minutes: 20, seconds: 0}
               check "Do NOT remove the output items (small PCR tubes on temperature block)."
            end
            
            robust_release_inputs ["Ligase", "MoClo Restriction Enzyme", "Vector", "Insert", "Buffer"], current_taken_items, interactive: true
            
            show do
                title "Set timer for storing outputs"
                check "Set a timer for 2 hrs, after which the reactions should be done incubating. At this point, you must reset the run to innactivate the temp block, and then store the output items (see following slides)."
               timer initial: { hours: 2, minutes: 0, seconds: 0}
            end
            
        else
            #dilute templates
            robust_take_inputs [TEMPLATE, FWD, REV], current_taken_items, interactive: true, method: "boxes"
            operations.running.each_with_index do |op, i|
                op.temporary[:aliquot_tube] = i+1
            end
            show do
                title "Create temporary diluted template aliquots"
                check "Thaw items #{(operations.running.map{|op| op.input(FWD).item} + operations.running.map{|op| op.input(REV).item}).to_sentence} in 37C incubator while continuing with the protocol."
                note "Get out #{operations.running.count} new 1.5 ml tubes and number them 1-#{operations.running.count}. Add DNA and water according to the following table:"
                table operations.start_table
                .custom_column(heading: "New tube number") { |op| "#{op.temporary[:aliquot_tube].to_s}"}
                .custom_column(heading: "DNA template to add", checkable: true) { |op| "#{(op.input("Template").object_type.name == "Small LB Overnight Culture") ? "10" : "1"} µl of #{op.input("Template").item.id}"}
                .custom_column(heading: "Water to add", checkable: true) { |op| "#{(op.input("Template").object_type.name == "Small LB Overnight Culture") ? "0" : "49"} µl of water"}
                .end_table
            end
            robust_release_inputs [TEMPLATE], current_taken_items, interactive: true, method: "boxes"
            
            robust_take_inputs ["dntp", "Buffer"], current_taken_items, interactive: true, method: "boxes"
            
            show do
                title "Combine water, buffer, and dNTPs"
                check "Label a 1.5 ml Eppendorf tube \"MM\" and place it on ice"
                check "Add reagents to \"MM\" according to the following chart:"
                table_matrix = Array.new {Array.new}
                table_matrix[0] = ["Water to add", "Buffer to add", "dNTP to add"]
                table_matrix[1] = [{content: water_for_mm.to_s, check: true} , Array.new, Array.new]
                mm_buffer_vol_by_item.each{|item, vol| table_matrix[1][1] << "#{vol.round(2)} µl of #{item.id}"}
                mm_dntp_vol_by_item.each{|item, vol| table_matrix[1][2] << "#{vol.round(2)} µl of #{item.id}"}
                table_matrix[1][1] = {content: table_matrix[1][1].join(", "), check: true}
                table_matrix[1][2] = {content: table_matrix[1][2].join(", "), check: true}
                table table_matrix
            end
            
            robust_release_inputs ["dntp"], current_taken_items, interactive: true, method: "boxes"
            
            show do
                title "Add reagents to PCR tubes"
                note "Get out #{operations.running.count} new PCR tubes, label and add reagents to PCR tubes according to the following table."
                table operations.start_table
                .output_item(FRAGMENT)
                .custom_column(heading: "Master mix (MM) to add", checkable: true) { |op| "#{((REACTION_VOLUME-input_volumes[FWD]-input_volumes[REV]-input_volumes[TEMPLATE]) / 2.0).round(2)} µl of MM"}
                .custom_column(heading: "Template tube # to add", checkable: true) { |op| "#{input_volumes[TEMPLATE].round(2)} µl of of tube ##{op.temporary[:aliquot_tube]}"}
                .custom_column(heading: "Forward Primer to add", checkable: true) { |op| "#{input_volumes[FWD].round(2)} µl of #{op.input("Forward Primer").item.id}"}
                .custom_column(heading: "Reverse Primer to add", checkable: true) { |op| "#{input_volumes[REV].round(2)} µl of #{op.input("Reverse Primer").item.id}"}
                .end_table
                check "Discard the diluted template tubes numbered 1-#{operations.running.count}"
            end
            
            robust_release_inputs [FWD, REV], current_taken_items, interactive: true, method: "boxes"
            
            robust_take_inputs ["Q5"], current_taken_items, interactive: true, method: "boxes"
            
            show do
                title "Dilute Q5"
                check "Label a 1.5 ml epindorf tube \"DP\" and place it on ice"
                check "Add reagents to \"DP\" according to the following chart:"
                table_matrix = Array.new {Array.new}
                table_matrix[0] = ["Water to add", "Buffer to add", "Q5 to add"]
                table_matrix[1] = [{content: water_for_dp.to_s, check: true} , Array.new, Array.new]
                dp_buffer_vol_by_item.each{|item, vol| table_matrix[1][1] << "#{vol.round(2)} µl of #{item.id}"}
                dp_q5_vol_by_item.each{|item, vol| table_matrix[1][2] << "#{vol.round(2)} µl of #{item.id}"}
                table_matrix[1][1] = {content: table_matrix[1][1].join(", "), check: true}
                table_matrix[1][2] = {content: table_matrix[1][2].join(", "), check: true}
                table table_matrix
            end
            
            robust_release_inputs ["Q5", "Buffer"], current_taken_items, interactive: true, method: "boxes"
        
            show do
                title "Add Diluted Q5 polymerase to PCR tubes"
                note "Add diluted Q5 polymerase to PCR tubes according to the following table"
                warning "Be sure to manully add note 'Q5' to all the new PCR samples in Aquarium"
                table operations.start_table
                .output_item(FRAGMENT)
                .custom_column(heading: "Diluted Q5 (DP) to add", checkable: true) { |op| "#{((REACTION_VOLUME-input_volumes[FWD]-input_volumes[REV]-input_volumes[TEMPLATE]) / 2.0).round(2)} µl of DP"}
                .end_table
            end
            
        end

        all_block_names = []
        TOTAL_THERMOCYCLERS.times do |tc_number|
            BLOCKS_PER_THERMOCYCLER.times do |block_number|
                all_block_names << "Thermocycler " + (tc_number+1).to_s + ", Block " + (block_number+1).to_s
            end
        end

        chosen_block_names = []
        data = show {
            title "Select blocks of thermocycler"
            if blocks_required > 1
                note "Select #{blocks_required} different thermocycler blocks (confirm they are available on the machine before selecting)."
            else
                note "Select the thermocycler block you would like to use (confirm it is available on the machine before selecting)."
            end
            blocks_required.times do |i|
                select all_block_names, var: "choice#{i}", label: "Block #", multiple: true, default: i
            end
        }
        blocks_required.times do |i|
            chosen_block_names << data["choice#{i}".to_sym]
        end
        log_info "chosen_block_names", chosen_block_names
        
        ########### Old code that uses a multi-select input instead of multiple single select inputs, should switch back to this if klavins lab ever fixes... ###########
        #chosen_block_names = []
        #if debug
        #    chosen_block_names = all_block_names[0..(blocks_required-1)]
        #else
        #    first_try = true
        #    while chosen_block_names.length != blocks_required
        #        data = show {
        #            title "Select blocks of thermocycler"
        #            warning "Wrong number of blocks selected." if not first_try
        #            note "Please select the #{blocks_required} thermocycler block(s) you would like to use."
        #            note "(use ctrl click to select multiple)"
        #            select all_block_names, var: "choice", label: "Block(s) #", multiple: true, default: (0..(blocks_required-1)).to_a
        #            }
        #        chosen_block_names = Array(data[:choice])
        #        first_try = false
        #    end
        #end

        op_array.each do |zones_in_block|
            block_name = chosen_block_names[0]
            lengths = zones_in_block.flatten.map {|op| op.output(FRAGMENT).sample.properties["Length"]}
            extension_time_seconds = [(lengths.max)/1000.0*30, 30.0].max
            extension_time_seconds = extension_time_seconds.ceil
            extension_time_minutes = 0
            while extension_time_seconds >= 60
                extension_time_seconds -= 60
                extension_time_minutes += 1
            end
            table_matrix = Array.new {Array.new}
            table_matrix[0] = ["Zone in #{block_name}", "PCR Result Item IDs" ]
            table_matrix[1] = ["Zone 1", []]
            table_matrix[2] = ["Zone 2", []]
            zone_1_tanneal = 0
            zone_2_tanneal = 0
            zones_in_block.each_with_index do |ops_in_zone, zone_index|
                if zone_index == 0
                    zone_1_tanneal = ops_in_zone[0].temporary[:tanneal]
                    zone_2_tanneal = ops_in_zone[0].temporary[:tanneal]
                elsif ops_in_zone.any? #if there is nothing in zone 2, leave zone 2 tanneal same as zone 1 tanneal
                    zone_2_tanneal = ops_in_zone[0].temporary[:tanneal]
                end
                ops_in_zone.each do |op|
                    table_matrix[zone_index+1][1] << op.output(FRAGMENT).item.id.to_s #loads IDs into a matrix to be displayed to user
                    op.output(FRAGMENT).item.move (block_name + ", Zone " + (zone_index+1).to_s)
                end
            end
            table_matrix[1][1] = table_matrix[1][1].join(", ")
            table_matrix[2][1] = table_matrix[2][1].join(", ")
            show do
                title "Place PCR reactions into #{block_name}"
                note "Place PCR reactions into #{block_name} according to the following table:"
                table table_matrix
            end
            
            show do
                title "Set up PCR cycle for #{block_name}"
                bullet "Select the circular \"Set Up Run\" button corresponding to #{block_name}"
                bullet "Select \"Open Method\", then \"Q5 PCR\" (located in DAMP1 folder)"
                bullet "Select the THIRD STEP in STAGE 2, and set its time to 0:0#{extension_time_minutes}:#{extension_time_seconds}"
                bullet "Select \"Edit\", \"Manage Steps\", \"Advanced Options\", \"VeriFlex\""
                bullet "Select the small edit icon (pencil) corresponding to the SECOND STEP in STAGE 2"
                bullet "Set Zone 1 temperature to #{zone_1_tanneal} and Zone 2 temperature to #{zone_2_tanneal}. Select \"Done\", \"Done\", \"Verify Block\", and \"Start Run\""
            end
            chosen_block_names.shift
        end
        store_outputs_with_volumes output_volumes, current_taken_items, interactive: false
        return {}
    end
end
