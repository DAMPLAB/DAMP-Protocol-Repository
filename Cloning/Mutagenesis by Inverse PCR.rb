needs "Standard Libs/Debug Lib"
needs "Cloning Libs/Cloning"
class Protocol
	include Debug
	include Cloning
	# I/O
	FWD = "Forward Primer"
	REV = "Reverse Primer"
	TEMPLATE = "Template"
	PRODUCT = "Mutagenesis Reaction Product"
    
    REACTION_VOLUME = 20.0
	TOTAL_THERMOCYCLERS = 1
	ANNEAL_TEMP_TOLERANCE = 1.0 # Reactions where the difference in annealing temp is less than this value may be run together

	BLOCKS_PER_THERMOCYCLER = 3
	ZONES_PER_BLOCK = 2
	REACTIONS_PER_ZONE = 16
	
	##Divide template stock by 10. Add 1.5 ul of this per 20 ul reaction.
	##Divide primer stocks by 3.75. Add 1.5 ul of this per 20 ul reaction.
    ##Primer and template can be diluted together
	def main
        current_taken_items = []
        # Remember to add volume information to input and output object types (and concentration data where applicable).
        # Different input volumes for small batches to avoid pipetting small amounts
        input_volumes = {FWD => (2.67*REACTION_VOLUME / 20.0).round(2), REV => (2.67*REACTION_VOLUME / 20.0).round(2), TEMPLATE => (REACTION_VOLUME / 20.0).round(2)}
        output_volumes = {PRODUCT => (REACTION_VOLUME*0.95 - 2.0).round}
        
        check_user_inputs [FWD, REV, TEMPLATE], input_volumes, current_taken_items
        return {} if check_for_errors
        
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
        
        #dilute templates
        robust_take_inputs [TEMPLATE, FWD, REV], current_taken_items, interactive: true
        operations.running.each_with_index do |op, i|
            op.temporary[:aliquot_tube] = i+1
        end
        
        show do
            title "Create temporary diluted template/primer aliquots"
            note "Get out #{operations.running.count} new 1.5 ml tubes and number them 1-#{operations.running.count}. Add template, primer, and water according to the following table:"
            table operations.start_table
		    .custom_column(heading: "New tube number") { |op| "#{op.temporary[:aliquot_tube].to_s}"}
		    .custom_column(heading: "DNA template to add", checkable: true) { |op| "#{input_volumes[TEMPLATE]} µl of #{op.input(TEMPLATE).item.id}"}
		    .custom_column(heading: "FWD primer to add", checkable: true) { |op| "#{input_volumes[FWD]} µl of #{op.input(FWD).item.id}"}
		    .custom_column(heading: "REV primer to add", checkable: true) { |op| "#{input_volumes[REV]} µl of #{op.input(REV).item.id}"}
		    .custom_column(heading: "Water to add", checkable: true) { |op| "#{10-input_volumes[TEMPLATE]-input_volumes[FWD]-input_volumes[REV]} µl of water"}
		    .end_table
        end
        robust_release_inputs [TEMPLATE, FWD, REV], current_taken_items, interactive: true
        
        show do
            title "Make master mix"
            check "Get out Q5 Site-Directed Mutagenesis Kit from the -20C freezer."
            warning "Keep kit contents on ice."
            note "Get out a 1.5 ml tube and label it \"MM\". Add reagents according to the following table:"
            table_matrix = Array.new(2) {Array.new}
            table_matrix[0] = ["Water to add", "Q5 Hot Start High-Fidelity 2X Master Mix to add"]
            table_matrix[1] << {content: "#{(operations.running.count*9.35).round(2)} µl", check: true}
            table_matrix[1] << {content: "#{(operations.running.count*11).round(2)} µl", check: true}
            table table_matrix
            check "Return Q5 Site-Directed Mutagenesis Kit to the freezer."
        end
        
        robust_make [PRODUCT], current_taken_items
        
        show do
		    title "Add reagents to reaction tubes"
		    note "Get out #{operations.running.count} new PCR tubes, label and add master mix to PCR tubes according to the following table."
		    table operations.start_table
		    .output_item(PRODUCT)
		    .custom_column(heading: "Master mix (MM) to add", checkable: true) { |op| "18.5 µl of MM"}
		    .custom_column(heading: "Template/primer tube to add", checkable: true) { |op| "1.5 µl of of tube ##{op.temporary[:aliquot_tube]}"}
		    .end_table
		    check "Discard the diluted template tubes numbered 1-#{operations.running.count}"
		    check "Discard empty \"MM\" tube."
		end
		
		all_block_names = []
		TOTAL_THERMOCYCLERS.times do |tc_number|
		    BLOCKS_PER_THERMOCYCLER.times do |block_number|
		        all_block_names << "Thermocycler " + (tc_number+1).to_s + ", Block " + (block_number+1).to_s
		    end
		end

		chosen_block_names = []
		if debug
		    chosen_block_names = all_block_names[0..(blocks_required-1)]
		else
		    first_try = true
		    while chosen_block_names.length != blocks_required
		        data = show {
		            title "Select blocks of thermocycler"
		            warning "Wrong number of blocks selected." if not first_try
		            note "Please select the #{blocks_required} thermocycler block(s) you would like to use."
		            note "(use ctrl click to select multiple)"
		            select all_block_names, var: "choice", label: "Block(s) #", multiple: true, default: (0..(blocks_required-1)).to_a
		            }
		        chosen_block_names = Array(data[:choice])
		        first_try = false
		    end
		end

		op_array.each do |zones_in_block|
		    block_name = chosen_block_names[0]
		    lengths = zones_in_block.flatten.map {|op| op.output(PRODUCT).sample.properties["Length"]}
		    extension_time_seconds = [(lengths.max)/1000.0*30, 30.0].max
		    extension_time_seconds = extension_time_seconds.ceil
		    extension_time_minutes = 0
		    while extension_time_seconds >= 60
		        extension_time_seconds -= 60
		        extension_time_minutes += 1
		    end
		    table_matrix = Array.new {Array.new}
		    table_matrix[0] = ["Zone in #{block_name}", "Mutagenesis Result Item IDs" ]
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
		            table_matrix[zone_index+1][1] << op.output(PRODUCT).item.id.to_s #loads IDs into a matrix to be displayed to user
		            #Does not actually "move" the items because they are going to be retreived by the tech before the end of the protocol.
		        end
		    end
		    table_matrix[1][1] = table_matrix[1][1].join(", ")
		    table_matrix[2][1] = table_matrix[2][1].join(", ")
		    show do
		        title "Place mutagenesis reactions into #{block_name}"
		        note "Place mutagenesis reactions into #{block_name} according to the following table:"
		        table table_matrix
		    end
		    
		    show do
		        title "Set up thermocycler settings for #{block_name}"
		        bullet "Select the circular \"Set Up Run\" button corresponding to #{block_name}"
                bullet "Select \"Open Method\", then \"Mutagenesis Q5 Kit\" (located in public folder)"
		        bullet "Select the THIRD STEP in STAGE 2, and set its time to 0:0#{extension_time_minutes}:#{extension_time_seconds}"
		        bullet "Select \"Edit\", \"Manage Steps\", \"Advanced Options\", \"VeriFlex\""
		        bullet "Select the small edit icon (pencil) corresponding to the SECOND STEP in STAGE 2"
		        bullet "Set Zone 1 temperature to #{zone_1_tanneal} and Zone 2 temperature to #{zone_2_tanneal}. Select \"Done\", \"Done\", \"Verify Block\", and \"Start Run\""
		        check "Set a timer to remind yourself when the thermocycler is done."
                warning "This is not the last step! Mutagenesis requires additional steps after the thermocycler is finished."
		    end
		    chosen_block_names.shift
		end
		
		show do
		    title "Transfer 1 µl to 1.5 ml tubes"
		    check "Take reactions out of the thermocycler and place on ice."
		    check "Transfer 1 µl of liquid from the small PCR tubes to new 1.5 ml tubes and label with the same IDs:"
		    table operations.start_table
		        .custom_column(heading: "New 1.5 ml tube ID") { |op| op.output(PRODUCT).item.id}
		        .custom_column(heading: "Mutagenesis reaction (small PCR tube) to add") {|op| {content: "1 µl of #{op.output(PRODUCT).item.id}", check: true}}
		        .end_table
            check "Discard small PCR tubes."
		end
		
		show do
            title "Make master mix 2"
            check "Get out Q5 Site-Directed Mutagenesis Kit from the -20C freezer."
            warning "Keep kit contents on ice."
            note "Get out a 1.5 ml tube and label it \"MM2\". Add reagents according to the following table:"
            table_matrix = Array.new(2) {Array.new}
            table_matrix[0] = ["Water to add", "2X KLD Reaction Buffer to add", "10X KLD Enzyme Mix to add"]
            table_matrix[1] << {content: "#{(operations.running.count*3.33).round(2)} µl", check: true}
            table_matrix[1] << {content: "#{(operations.running.count*5.5).round(2)} µl", check: true}
            table_matrix[1] << {content: "#{(operations.running.count*1.1).round(2)} µl", check: true}
            table table_matrix
            check "Return Q5 Site-Directed Mutagenesis Kit to the freezer."
        end
        
        show do
		    title "Add reagents to reaction tubes"
		    note "Add master mix 2 to tubes according to the following table:"
		    table operations.start_table
		    .output_item(PRODUCT)
		    .custom_column(heading: "Master mix (MM2) to add", checkable: true) { |op| "9 µl of MM2"}
		    .end_table
		    check "Discard empty \"MM2\" tube."
		end
		
		show do
		    title "Incubate reactions"
		    check "Incubate items #{operations.running.map{|op| op.output(PRODUCT).item}.to_sentence} for 30 minutes at 37C"
		    timer initial: { hours: 0, minutes: 30, seconds: 0}
		end
		
		store_outputs_with_volumes output_volumes, current_taken_items, interactive: true
		return {}
	end
end
