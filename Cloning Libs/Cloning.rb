module Cloning
  require 'net/smtp'

  def check_concentration operations, input_name
    items = operations.collect { |op| op.input_array(input_name).items.select { |i| i.get(:concentration).nil? } }.flatten.uniq
    
    cc = show do
      title "Please nanodrop the following #{items.first.object_type.name.pluralize}"
      note "Please nanodrop the following #{items.first.object_type.name.pluralize}:"
      items.each do |i|
        get "number", var: "c#{i.id}", label: "#{i} item", default: 42
      end
    end if items.any?
    
    items.each do |i|
      i.associate(:concentration, cc["c#{i.id}".to_sym])
      i.save
    end
  end
  
    
  # The check_volumes method will have the lab tech ensure that the given input item volumes are above a certain minimum amount, 
  # for each operation. The inputs to check are specified in an array parameter. 
  # The minimum volume is specified in mL on a per-operation basis using the the value stored in op.temporary[<vol_sym>],
  # where vol_sym is a symbol name of your choice.
  # Contamination can be checked for too, with the additional option parameter check_contam: true
  # After determining which inputs for which ops are low volume, this method passes off a hash of 'items -> lists of ops' to your rebuilder function specified by name as string or symbol in the callback argument.
  # when the callback method returns, check_volumes loops back and checks the volumes again of the newly assigned unverified input items, and repeats this loop until all given inputs for all ops are verified for their volume.
  # for a detailed example of how this method can be used, look at the method call in make PCR fragment, and the callback function make_aliquots_from_stock
  def check_volumes inputs, vol_sym, callback, options = {}
    
    ops_by_item = Hash.new(0)
    operations.running.each do |op|
      inputs.each do |input|
        if ops_by_item.keys.include? op.input(input).item
          ops_by_item[op.input(input).item].push op
        else
          ops_by_item[op.input(input).item] = [op] 
        end
      end
    end
      
    # while any operations for any of the specified inputs are unverified, check the volumes again and send any bad op/input combos to rebuilder function
    while ops_by_item.keys.any?
      verify_data = show do
        title "Verify enough volume of each #{inputs.to_sentence(last_word_connector: ", or")} exists#{options[:check_contam] ? ", or note if contamination is present" : ""}"
        
        ops_by_item.each do |item, ops| 
          volume = 0.0
          ops.each { |op| volume += op.temporary[vol_sym] }
          volume = (volume*100).round / 100.0
          choices = options[:check_contam] ? ["Yes", "No", "Contamination is present"] : ["Yes", "No"]
          select choices, var: "#{item.id}", label: "Is there at least #{volume} µL of #{item.id}?", default: 0
        end
      end
      ops_by_item.each do |item, ops|
        if verify_data["#{item.id}".to_sym] == "Yes"
          ops_by_item.except! item
        elsif verify_data["#{item.id}".to_sym] == "Contamination is present"
          item.associate(:contaminated, "Yes")
          item.save
        end
      end
      method(callback.to_sym).call(ops_by_item, inputs) if ops_by_item.keys.any?
    end
  end
  
  # a common callback for check_volume.
  # takes in lists of all ops that have input aliquots with insufficient volume, sorted by item,
  # and takes in the inputs which were checked for those ops.
  # Deletes bad items and remakes each primer aliquots from primer stock
  def make_aliquots_from_stock bad_ops_by_item, inputs
    # bad_ops_by_item is accessible by bad_ops_by_item[item] = [op1, op2, op3...]
    # where each op has a bad volume reading for the given item
    
    # Construct list of all stocks needed for making aliquots. Error ops for which no primer stock is available
    # for every non-errored op that has low item volume,
    # replace the old aliquot item with a new one. 
    aliquots_to_make = 0
    stocks = []
    ops_by_fresh_item = Hash.new(0)
    found_items = []
    stock_table = [["Primer Stock ID", "Primer Aliquot ID"]]
    transfer_table = [["Old Aliquot ID", "New Aliquot ID"]]
    bad_ops_by_item.each do |item, ops|
        
      #first, check to see if there is a replacement aliquot availalbe in the inventory
      fresh_item = item.sample.in("Primer Aliquot").reject {|i| i == item }.first
      
      if fresh_item
        #if a replacement item was found in the inventory, snag it
        found_items.push fresh_item
      else
        # no replacement, found, lets try making one.
        stock = item.sample.in("Primer Stock").first
        if stock.nil?
          # no stock found, replacement could not be made or found: erroring operation
          ops.each { |op| op.error :no_primer_stock, "aliquot #{item.id} was bad and a replacement could not be made. You need to order a primer stock for primer sample #{item.sample.id}." }
          bad_ops_by_item.except! item
        else
          stocks.push stock
          aliquots_to_make += 1
          fresh_item = produce new_sample item.sample.name, of: item.sample.sample_type.name, as: item.object_type.name
          stock_table.push [stock.id, {content: fresh_item.id, check: true}]
        end
      end
      
      if fresh_item
        # for the items where a replacement is able to be found or made, update op item info
        item.mark_as_deleted
        bad_ops_by_item.except! item
        ops_by_fresh_item[fresh_item] = ops
        ops.each do |op| 
          input = inputs.find { |input| op.input(input).item == item }
          op.input(input).set item: fresh_item
        end
        if item.get(:contaminated) != "Yes"
          transfer_table.push [item.id, {content: fresh_item.id, check: true}]    
        end
      end
    end
    
    take found_items, interactive: true if found_items.any?
    #items are guilty untill proven innocent. all the fresh items will be put back into the list of items to check for volume
    bad_ops_by_item.merge! ops_by_fresh_item
    take stocks, interactive: true if stocks.any?
    
    # label new aliquot tubes and dilute
    show do 
      title "Grab 1.5 mL tubes"
      
      note "Grab #{aliquots_to_make} 1.5 mL tubes"
      note "Label each tube with the following ids: #{bad_ops_by_item.keys.reject { |item| found_items.include? item }.map { |item| item.id }.sort.to_sentence}"
      note "Using the 100 uL pipette, pipette 90 µl of water into each tube"
    end if bad_ops_by_item.keys.reject { |item| found_items.include? item }.any?
  
    # make new aliquots
    show do 
      title "Transfer primer stock into primer aliquot"
      
      note "Pipette 10 uL of the primer stock into the primer aliquot according to the following table:"
      table stock_table
    end if stocks.any?
    
    
    if transfer_table.length > 1
      show do
        title "Transfer Residual Primer"
        
        note "Transfer primer residue from the low volume aliquots into the fresh aliquots according to the following table:"
        table transfer_table
      end
    end
    
    release stocks, interactive: true if stocks.any?
  end

  
  
  
  # Associates specified associations + uploads from :from to :to. This is used primarily to pass sequencing results through items in a plasmid's lineage
  #   e.g., pass_data "sequence_verified", "sequencing results", from: overnight, to: glycerol_stock
  #   This will copy all sequencing results and the sequence_verified associations from the overnight to the glycerol stock
  def pass_data *names, **kwargs
    from = kwargs[:from]
    to = kwargs[:to]
    names.each do |name|
      keys = from.associations.keys.select { |k| k.include? name }
      keys.each do |k|
        to.associate k, from.get(k), from.upload(k)
      end
    end
  end
  
  
  # Takes an array of items as input and asks the user if they would like to dispose of them. If note (string) is also given then this will be displayed to the user as well
  # Note that this doesn't store items the user doesn't want to get rid of.
  # Example: ask_to_delete items, "Discard empty tubes."
  def ask_to_delete items, note=nil
    data = show do
        title "Select any items to delete"
        note note if not note.blank?
        items.each_with_index { |item, item_index| select [ "Keep this item", "Delete this item" ], var: "#{item_index}", label: "#{item.sample.name} (#{item.id})", default: 0}
    end
    data.each do |key, choice|
        if choice == "Delete this item"
            items[key.to_s.to_i].mark_as_deleted
        end
    end
  end
  
  
  # Takes an item as input and (optionally) a number to get out, returns a string as output which says "If more samplename is needed, get out itemID1 (location), itemID2 (location), etc." 
  # "start" argument determines which item to show. This should usually be set to be equal to the number of items of this type that the user currently has out already.
  # Default number of extra items to show is 1.
  # Example 1: find_more dNTP_item
  # Example 2: find_more dNTP_item, 2
  def find_more item, start=1, number=1
    sample_name = item.sample.name
    object_type = item.object_type
    items = Array(find(:sample, name: sample_name)[0].in(object_type.name)[start..number])
    items_and_locs = items.map {|i| i.id.to_s + " (" + i.location + ")"}
    if items_and_locs.empty?
        return "There are no extra #{sample_name} items other than the one you are using. Consider ordering/making more."
    else
        return "If more #{sample_name} is needed, get out #{items_and_locs.to_sentence} and put away when done."
    end
  end
  
  # Used after actions which may cause operations to error. Informs the technician of how many have errored. Also, returns true if all are errored.
  def check_for_errors
    new_errored_ops = operations.errored.select{|op| !(op.temporary[:sent_error_message] == true)}
    if new_errored_ops.count > 0
        errored_users = new_errored_ops.map{|op| User.find(op.user_id).name}.uniq.to_sentence
        data = show do
            title "Some of the scheduled operations have been cancelled"
            warning "A total of #{operations.errored.count}/#{operations.count} operations have been cancelled due to errors."
            select ["Send email", "Do not send"], var: "email_choice", label: "Would you like to notify #{errored_users} by email that the following operations have been cancelled?", default: 0
            new_errored_ops.each do |op|
                note op.associations.map{|key, value| "<b>Operation ID:</b> #{op.id} <b>Operation Name:</b> #{op.name} <b>Info:</b> #{key}, #{value}"}.join("\n")
            end
        end
        new_errored_ops.each{|op| op.temporary[:sent_error_message] = true}
        
        if data[:email_choice] == "Send email"
            send_error_emails new_errored_ops
        end
        
        if operations.running.count == 0
            return true
        else
            return false
        end
    end
  end
  
  # Centrifugation. Takes a list of items or list of IDs or (string and a number), rpm or rcf value, and an amount of time. Tells the user to centrifuge the items and shows how to balance that number of tubes in a 24-hole 
  # microcentrifuge. Number argument is not required unlesss using a string as items.
  
  #def centrifuge_items(items:, number:, rpm:, rcf:, min:)
    #stuff
  #end

  #centrifuge_items(items: items, rpm: 1000, min: 3)
  
  
  
    #def set_inputs_within_spec operations, input_name, min_conc, min_amount
    #    operations.each do |op|
    #        type = op.input(input_name).object_type
    #        sample = op.input(input_name).sample
    #        items_by_info = sample.items.partition {|i| (i.get :concentration).present? && (i.get :volume).present?}
    #        items_meeting_spec = items_by_info[0].select {|i| (i.get :concentration) >= min_conc && 1.1*(i.get :concentration)*(i.get :volume) >= min_amount}
    #        if items_meeting_spec.any?
    #            op.input("Enzyme").set item: items_meeting_spec.first
    #        else
    #            
    #            op.error :no_suitable_inputs, "No items of #{sample.name} meet minimum specifications for protocol."
    #        end
    #    end
    #    show do
    #        
    #    end
    #end
    
    
    
    
    
  # a NEW EXPERIMENTAL callback for check_volume.
  # takes in lists of all ops that have input aliquots with insufficient volume, sorted by item,
  # and takes in the inputs which were checked for those ops.
  # Deletes bad items and replaces with "stock" enzymes (moving them from stock to aliquot)
  def make_enzyme_aliquots_from_stock bad_ops_by_item, inputs
    # bad_ops_by_item is accessible by bad_ops_by_item[item] = [op1, op2, op3...]
    # where each op has a bad volume reading for the given item
    
    # Construct list of all stocks needed for making aliquots. Error ops for which no primer stock is available
    # for every non-errored op that has low item volume,
    # replace the old aliquot item with a new one. 
    aliquots_to_make = 0
    stocks = []
    ops_by_fresh_item = Hash.new(0)
    found_items = []
    stock_table = [["Enzyme Stock Name", "Enzyme Aliquot ID (new item)"]]
    transfer_table = [["Old Aliquot ID", "New Aliquot ID"]]
    bad_ops_by_item.each do |item, ops|
        
      #first, check to see if there is a replacement aliquot availalbe in the inventory
      fresh_item = item.sample.in("Enzyme Work Solution").reject {|i| i == item }.first
      
      if fresh_item
        #if a replacement item was found in the inventory, snag it
        found_items.push fresh_item
      else
        # no replacement, found, lets try making one.
        stock = item.sample.in("Enzyme Stock").first
        if stock.nil?
          # no stock found, replacement could not be made or found: erroring operation
          ops.each { |op| op.error :no_primer_stock, "Aliquot #{item.id} was bad and a replacement could not be made. You need to order an enzyme stock for sample #{item.sample.id}." }
          bad_ops_by_item.except! item
        else
          stocks.push stock
          aliquots_to_make += 1
          fresh_item = produce new_sample item.sample.name, of: item.sample.sample_type.name, as: item.object_type.name
          stock_table.push ["#{stock.sample.name} (old ID: #{stock.id})", {content: fresh_item.id, check: true}]
        end
      end
      
      if fresh_item
        # for the items where a replacement is able to be found or made, update op item info
        item.mark_as_deleted
        bad_ops_by_item.except! item
        ops_by_fresh_item[fresh_item] = ops
        ops.each do |op|
          input = inputs.find { |input| op.input(input).item == item }
          op.input(input).set item: fresh_item
        end
        if item.get(:contaminated) != "Yes"
          transfer_table.push [item.id, {content: fresh_item.id, check: true}]
        end
      end
    end
    
    take found_items, interactive: true if found_items.any?
    #items are guilty untill proven innocent. all the fresh items will be put back into the list of items to check for volume
    bad_ops_by_item.merge! ops_by_fresh_item
    take stocks, interactive: true if stocks.any?
    
    # label new aliquot tubes and dilute
    #show do 
    #  title "Grab 1.5 mL tubes"
    #  
    #  note "Grab #{aliquots_to_make} 1.5 mL tubes"
    #  note "Label each tube with the following ids: #{bad_ops_by_item.keys.reject { |item| found_items.include? item }.map { |item| item.id }.sort.to_sentence}"
    #  note "Using the 100 uL pipette, pipette 90uL of water into each tube"
    #end if bad_ops_by_item.keys.reject { |item| found_items.include? item }.any?
  
    # make new aliquots
    show do 
      title "Convert enzyme stocks to aliquots and label with new IDs"
      
      note "Relabel enzyme stocks with the following IDs. These stocks will be converted to aliquots and stored in the small freezer."
      note "If the enzyme stock was already labelled with an old ID, clean it off before continuing."
      table stock_table
    end if stocks.any?
    
    
    if transfer_table.length > 1
      show do
        title "Transfer residual enzyme to new aliquot"
        note "Transfer residual enzyme from the low volume aliquots into the fresh aliquots according to the following table:"
        table transfer_table
      end
    end
    
    release stocks, interactive: true if stocks.any?
  end

    def nanodrop_dsdna items
        conc_data = show do
          title "Please nanodrop the following items using dsDNA setting on nanodrop."
          note "Please nanodrop the following items using dsDNA setting on nanodrop and enter concentrations in ng/µl."
          check "Move the pipette tip in circles at the bottom of the tube for 10 seconds before nanodropping each item to ensure they are fully mixed."
          items.each do |i|
            get "number", var: "c#{i.id}", label: "#{i} item ng/µl", default:  (debug ? (Random.rand*1000) : 0)
            get "number", var: "A260280_#{i.id}", label: "#{i} item A260/A280", default:  1.8
            get "number", var: "A260230_#{i.id}", label: "#{i} item A260/A230", default:  1.8
          end
        end if items.any?
        
        items.each do |item|
            if item.sample.properties["Length"] == 0
                item.associate(:concentration, nil)
                item.associate(:concentration_keyword, "UNKNOWN")
                item.append_notes "Concentration of this item could not be calculated. Please enter length information."
                item.save
            else
                conc_in_ng_per_ul = conc_data["c#{item.id}".to_sym]
                # Hard coded concentration adjustment for purify gel slice operation. Based on running gel extraction blank and measuring concentration.
                if operations[0].operation_type.id == 482
                    conc_in_ng_per_ul = [(conc_in_ng_per_ul - 2.7), 0.0].max
                end
                conc_in_mol_per_l = conc_in_ng_per_ul * 0.0000015150 / item.sample.properties["Length"]
                item.associate(:concentration, conc_in_mol_per_l)
                item.associate(:A260280, conc_data["A260280_#{item.id}".to_sym])
                item.associate(:A260230, conc_data["A260230_#{item.id}".to_sym])
                item.associate(:volume, item.get(:volume).to_f - 1.0) if item.get(:volume)
                item.save
            end
        end if items.any?
    end
      
    def manually_enter_uM_conc items
        conc_data = show do
          title "Please determine and enter concentrations of the following items in µM."
          note "Please determine and enter concentrations of the following items in µM."
          warning "Do not enter concentration in ng/ul or any unit other than µM."
          items.each do |i|
            get "number", var: "c#{i.id}", label: "#{i} item", default:  (debug ? Random.rand * 100 : 0)
          end
        end if items.any?
        
        items.each do |item|
            item.associate(:concentration, conc_data["c#{item.id}".to_sym] / 1000000.0)
            item.save
        end if items.any?
    end

    def assign_input_items inputs, input_volumes, current_taken_items
        items_to_characterize = []
        #finds all items matching input sample and object type
        inputs.each do |input|
            operations.running.each do |op|
                if op.input_array(input).any?
                    op.input_array(input).each do |input_fields|
                        Array(input_fields.sample.in(input_fields.object_type.name)).each{|item| items_to_characterize << item}
                    end
                end
            end
        end
        
        items_to_characterize.uniq!
        items_to_release = characterize items_to_characterize, current_taken_items
        robust_release items_to_release, current_taken_items, interactive: true
        
        operations.running.each do |op|
            inputs.each do |input|
                if op.input_array(input).any?
                    item_array = []
                    op.input_array(input).each do |input_fields|
                        eligible_items = Array(input_fields.sample.in(input_fields.object_type.name)).select{|item| !item.deleted? && (!input_volumes.keys.include?(input) || item.get(:volume).to_f >= input_volumes[input]) && !(item.get(:concentration_keyword) == "UNKNOWN") && !(item.get(:concentration_keyword) == "UNKNOWN")}
                        #Use normal concentration items first, pick the smallest volume item
                        eligible_items.sort_by! {|item| [(item.get(:concentration_keyword) == "STANDARD") ? 0 : 1, input_volumes.keys.include?(input) ? item.get(:volume).to_f : 1]}
                        #if the item has custom wizards, get the item from the smallest custom wizard
                        begin
                            eligible_items.sort_by! {|item| item.object_type.data_object[:custom_wizards][item.locator.wizard.name.to_sym]} if input_fields.object_type.data_object[:custom_wizards]
                        rescue
                        end
                        if eligible_items.any?
                            item_array << eligible_items[0]
                            eligible_items[0].associate(:volume,(eligible_items[0].get(:volume).to_f - input_volumes[input].to_f).round(2)) if input_volumes.keys.include?(input)
                            eligible_items[0].save
                        else
                            op.error :input_volume_error, "Inadequate amount of input sample (name: #{op.input(input).sample.name} ID:#{op.input(input).sample.id})."
                        end
                    end
                    if !(op.status == "error")
                        item_array.each_with_index do |item, i|
                            op.input_array(input)[i].set item: item
                        end
                    end
                end
            end
        end
    end
    
    def check_user_inputs inputs, input_volumes, current_taken_items
        #Characterizes all possible input items rather than only user specified inputs simply to increase the number of characterized items in inventory
        items_to_characterize = []
        #finds all items matching input sample and object type
        inputs.each do |input|
            operations.running.each do |op|
                if op.input_array(input).any?
                    op.input_array(input).each do |input_fields|
                        Array(input_fields.sample.in(input_fields.object_type.name)).each{|item| items_to_characterize << item}
                    end
                end
            end
        end
        
        items_to_characterize.uniq!
        items_to_release = characterize items_to_characterize, current_taken_items
        robust_release items_to_release, current_taken_items, interactive: true
        
        #Check if user assigned items have sufficient volumes for operations
        
        operations.running.each do |op|
            inputs.each do |input|
                if op.input_array(input).any?
                    op.input_array(input).items.each_with_index do |input_item, input_index|
                        if !input_item.deleted? &&(!input_volumes.keys.include?(input) || input_item.get(:volume).to_f >= input_volumes[input]) && input_item.get(:concentration_keyword) != "UNKNOWN"
                            input_item.associate(:volume,(input_item.get(:volume).to_f - input_volumes[input].to_f).round(2)) if input_volumes.keys.include?(input)
                            input_item.save
                        else
                            if input_item.get(:concentration_keyword) == "UNKNOWN"
                                op.error :unknown_conc_error, "Concentration of input item could not be calculated, please confirm that length is not set to zero (Item ID:#{input_item.id}, Sample Name: #{input_item.sample.name})."
                            else
                                op.error :input_volume_error, "Inadequate amount of input item (Item ID:#{input_item.id}, Sample Name: #{input_item.sample.name})."
                            end
                        end
                    end
                end
            end
        end
    end
      
    def characterize all_items, current_taken_items
        #returns the list of items but with low concentration ones deleted and high concentration ones diluted/spread out
        #check if concentration_keyword is a string
        #check if volume is there
        #if there's a rec conc, nanodrop it.
        #if length is 0, associate concentration_keyword: "UNKNOWN" and associate a warning. Otherwise
        #tells the user to discard stuff or dilute stuff, deletes discarded items
        #should always save volumes as being lower than they actually are
        
        items_to_return = all_items
        
        #Smoothly converts old concentration data (which was in ng/ul) to the new type
        #TODO: delete this once all old inventory is transferred over
        items_to_return.each do |item|
            if item.get(:concentration) && item.get(:concentration_keyword).nil?
                if item.object_type.data_object[:conc_callback] == "nanodrop_dsdna"
                    conc_in_mol_per_l = item.get(:concentration).to_f * 0.0000015150 / item.sample.properties["Length"]
                    item.associate(:concentration, conc_in_mol_per_l)
                    item.save
                end
            end
        end
        
        #Smoothly detects and calculates concentrations of primer stocks from old system (which were at 100 uM)
        #TODO: delete this once all old inventory is transferred over
        items_to_return.each do |item|
            if item.sample.sample_type.name == "Primer" && item.object_type.name == "Primer Stock" && item.get(:volume).nil? && item.created_at < DateTime.new(2018,2,24)
                item.associate(:concentration, 0.0001)
                item.save
            end
        end
        
        items_requesting_delete = items_to_return.select{|i| !i.get(:delete_requested).nil?}
        
        robust_take items_requesting_delete, current_taken_items, interactive: true
        
        show do
            title "Discard items as requested by users."
            note "Some items have been requested for deletion by their respective users. Discard the following items:"
            note items_requesting_delete.map{|i| i.id}.to_sentence
        end if items_requesting_delete.any?
        
        items_requesting_delete.each do |item|
            items_to_return.delete(item)
            item.mark_as_deleted
        end
        
        items_to_measure_conc = items_to_return.reject {|item| item.object_type.data_object[:conc_callback].nil? || item.get(:concentration)}
        robust_take items_to_measure_conc, current_taken_items, interactive: true
        items_to_measure_conc_by_callback = {}
        items_to_measure_conc.each do |item|
            if !items_to_measure_conc_by_callback.keys.include? item.object_type.data_object[:conc_callback]
                items_to_measure_conc_by_callback[item.object_type.data_object[:conc_callback]] = [item]
            else
                items_to_measure_conc_by_callback[item.object_type.data_object[:conc_callback]] << item
            end
        end
        items_to_measure_conc_by_callback.each do |callback, items|
            method(callback.to_sym).call(items)
        end
        
        items_to_discard = []
        items_to_dilute = []
        items_to_return.select{|item| item.get(:concentration)}.each do |item|
            if item.get(:concentration).to_f < item.object_type.data_object[:min_conc].to_f
                items_to_discard << item
                item.mark_as_deleted
                items_to_return.delete(item)
                item.save
            elsif (100.0*item.get(:concentration).to_f / item.object_type.data_object[:rec_conc].to_f).round < 100
                item.associate :concentration_keyword, "LOW"
                item.append_notes "\nConcentration of this item is #{(100.0*item.get(:concentration).to_f / item.object_type.data_object[:rec_conc].to_f).round}% of recommended concentration. Yield of downstream applications may be reduced."
                item.save
            elsif (100.0*item.get(:concentration).to_f / item.object_type.data_object[:rec_conc].to_f).round > 100
                items_to_dilute << item
            else
                item.associate :concentration_keyword, "STANDARD"
            end
        end
        
        robust_take items_to_discard, current_taken_items
        
        #check if any below minimum conc items are operation outputs and throw errors if they are
        operations.running.each do |op|
            op.outputs.each do |output|
                if items_to_discard.include? output.item
                    op.error :output_below_min_conc, "Output item #{output.item.id} (#{output.sample.name}) was below the minimum concentration for its object type."
                end
            end
        end
        
        show do
            title "Discard low concentration items."
            note "Some items are below the minimum concentration for their object type. Discard the following items:"
            note items_to_discard.map{|i| i.id}.to_sentence
        end if items_to_discard.any?
        
        items_to_discard = []
        items_to_measure_vol = items_to_return.reject {|item| item.get(:volume) || item.object_type.data_object[:max_vol].nil?}
        robust_take items_to_measure_vol, current_taken_items, interactive: true if items_to_measure_vol.any?

        vol_data = show do
            title "Measure volumes of the following items"
            note "Measure volumes of the following items using a pipette or other appropriate means. Enter volumes in µl."
            warning "Remember to record volumes in µl and not ml."
            items_to_measure_vol.each do |item|
                get "number", var: "v#{item.id}", label: "#{item} item", default: (debug ? Random.rand*20.0 + 50.0 : 0)
            end
        end if items_to_measure_vol.any?
        
        items_to_measure_vol.each do |item|
            if (vol_data["v#{item.id}".to_sym].to_f)*0.95-2.0 > 0.0
                item.associate :volume, ((vol_data["v#{item.id}".to_sym].to_f)*0.95-2.0)
                item.save
            else
                items_to_discard << item
                item.mark_as_deleted
                items_to_dilute.delete(item) if items_to_dilute.include? item
                items_to_return.delete(item)
                item.save
            end
        end
        
        show do
            title "Discard low volume items."
            note "Discard the following low volume items:"
            check items_to_discard.map{|i| i.id}.to_sentence
        end if items_to_discard.any?
        
        split_counts_by_item = {}
        items_to_dilute.each do |item|
            if item.get(:concentration) && item.get(:volume)
                split_count = ((item.get(:concentration).to_f * item.get(:volume).to_f / item.object_type.data_object[:rec_conc].to_f) / item.object_type.data_object[:max_vol].to_f).ceil
                if (split_count > 0 && split_count < 100) #guards against accidental overload due to messy data
                    split_counts_by_item[item] = split_count
                else
                    raise "Split count error (see \"Cloning Libs/Cloning\" library. Split count was set to #{split_count} due to bad concentration or volume information."
                end
            end
        end
        
        robust_take items_to_dilute, current_taken_items, interactive: true if items_to_dilute.any?
        
        show do 
            title "Split contents of high concentration items to new containers before diluting."
            note "For pipetting accuracy reasons, the following items will be diluted in new tubes, and the original item tubes will be emptied and discarded."
            split_counts_by_item.reject{|i, c| c == 1}.each do |item, split_count|
                new_items = []
                split_volume = (item.get(:volume).to_f / split_count.to_f)
                item.associate(:volume, split_volume.round(2))
                item.save
                (split_count-1).times do
                    new_item = produce new_sample item.sample.name, of: item.sample.sample_type.name, as: item.object_type.name
                    pass_data *(item.associations.keys), from: item, to: new_item
                    new_item.save
                    new_item.associate(:volume, split_volume.round(2))
                    new_item.save
                    current_taken_items << new_item
                    items_to_return << new_item
                    items_to_dilute << new_item
                    new_items << new_item
                end
                check "Transfer #{item.get(:volume).round(2)} µl from item #{item.id} to #{split_count} new containers labelled #{(new_items.map{|i| i.id} << item.id).to_sentence}."
                check "Discard the original (now empty) container for #{item.id}"
            end
        end if split_counts_by_item.any? {|i, c| c > 1}
        
        show do
            title "Dilute the following items"
            check "Dilute items according to the following table:"
            table_matrix = Array.new(items_to_dilute.count+1) {Array.new}
            table_matrix[0] = ["Item ID", "Water to add"]
            items_to_dilute.each_with_index do |item, item_index|
                dilution_factor = item.get(:concentration).to_f / item.object_type.data_object[:rec_conc].to_f
                volume_to_add = ((dilution_factor - 1.0)*item.get(:volume).to_f).round(2)
                new_volume = ((item.get(:volume).to_f+volume_to_add)*0.95-2.0).round(2)
                item.associate(:volume, new_volume)
                item.associate(:concentration, item.object_type.data_object[:rec_conc].to_f)
                item.associate(:concentration_keyword, "STANDARD")
                item.save
                table_matrix[item_index+1] = [item.id.to_s, {content: "#{volume_to_add} µl of water", check: true}]
            end
            table table_matrix
        end if items_to_dilute.any?
        
        return items_to_return
    end
      
    def store_outputs_with_volumes output_volumes, current_taken_items, args = {}
        options = {
            interactive: false,
            method: "boxes"
            }.merge args
        items_to_characterize = []
        output_volumes.each do |output, vol|
            operations.running.each do |op|
                if op.output_array(output)
                    op.output_array(output).items.each do |item|
                        item.associate(:volume, vol.round(2))
                        item.save
                        items_to_characterize << item
                    end
                end
            end
        end
        if options[:interactive]
            characterize items_to_characterize, current_taken_items
        end
        robust_release items_to_characterize, current_taken_items, options
    end
      
    def robust_take items, current_taken_items, options={}
        items.uniq!
        items_to_take = items.reject{|item| current_taken_items.include? item || item.deleted?}
        take items_to_take, options if items_to_take.any?
        items_to_take.each{|i| current_taken_items << i}
    end
      
    def robust_release items, current_taken_items, options={}
        items.uniq!
        items.reject! {|item| (!current_taken_items.include? item) || item.deleted?}
        #Workaround to allow defining custom wizards in object_type data. Should be rewritten if custom wizard functionality is built in.
        items.each do |item|
            #similar to internal structure of item.store but supports custom wizards
            custom_wizards = item.object_type.data_object[:custom_wizards]
            if !(custom_wizards.nil?)
                stored = false
                wiz_index = 0
                while !stored && wiz_index < custom_wizards.keys.count
                    already_in_wiz = false
                    wiz_name = custom_wizards.keys[wiz_index]
                    max_in_wiz = custom_wizards[wiz_name]
                    wiz = Wizard.find_by_name(wiz_name.to_s)
                    num_in_wiz = 0
                    #check how many items are already there (other than the one being stored)
                    item.sample.items.each do |i|
                        if i.locator_id && Locator.find(i.locator_id).wizard.id == wiz.id
                            if i == item
                                already_in_wiz = true
                                stored = true
                            else
                                num_in_wiz += 1
                            end
                        end
                    end
                    if !already_in_wiz && num_in_wiz < max_in_wiz.round
                        #Closely mimics store and move_to in item.rb but with wizard not determined by object type.
                        locator = wiz.next
                        locstr = wiz.int_to_location locator.number
                        locs = Locator.where(wizard_id: wiz.id, number: (wiz.location_to_int locstr))
                        
                        case locs.length 
                        when 0
                            newloc = wiz.addnew locstr
                        when 1
                            newloc = locs.first 
                        end
                        
                        if newloc.item_id == nil
                            oldloc = Locator.find_by_id(item.locator_id)
                            oldloc.item_id = nil if oldloc
                            item.locator_id = newloc.id
                            item.set_primitive_location(locstr)
                            item.quantity = 1
                            item.inuse = 0
                            newloc.item_id = item.id
                            item.save
                            oldloc.save if oldloc
                            newloc.save
                            item.reload
                            oldloc.reload if oldloc
                            newloc.reload
                        end
                        stored = true
                    end
                    wiz_index += 1
                end
            end
        end
        release items, options if items.any?
        items.each{|i| current_taken_items.delete(i)}
    end
      
    def robust_take_inputs inputs, current_taken_items, options={}
        item_list = []
        inputs.each do |input|
            operations.running.each do |op|
                if op.input_array(input).any?
                    op.input_array(input).items.each do |item|
                        item_list << item
                    end
                end
            end
        end
        robust_take item_list, current_taken_items, options
    end
      
    def robust_release_inputs inputs, current_taken_items, options={}
        item_list = []
        inputs.each do |input|
            operations.running.each do |op|
                if op.input_array(input).any?
                    op.input_array(input).items.each do |item|
                        item_list << item
                    end
                end
            end
        end
        
        empty_item_list = item_list.select{|i| i.get(:volume) && i.get(:volume).to_f <= 1.0} #TODO: change to something more flexible (rather than just deleting if below 1 ul)
        empty_item_list.each do |i| 
            i.mark_as_deleted
            i.save
        end
        
        show do
            title "Discard low volume items."
            note "Discard the following low volume items:"
            check empty_item_list.map{|item| item.id}.uniq.to_sentence
        end if empty_item_list.any?
        robust_release item_list, current_taken_items, options
    end
      
    def robust_make outputs, current_taken_items
        operations.running.make only: outputs
        outputs.each do |output|
            operations.running.each do |op|
                if op.output_array(output).any?
                    op.output_array(output).items.each do |item|
                        current_taken_items << item
                    end
                end
            end
        end
    end
    
    def send_error_emails operations
        ops_by_user = {}
        operations.each do |op|
            user = User.find(op.user_id)
            if ops_by_user.keys.include? user
                ops_by_user[user] << op
            else
                ops_by_user[user] = [op]
            end
        end
        ops_by_user.each do |user, ops|
            body = "
            Hello #{user.name},<br/><br/>
            The following operations submitted to DAMP Lab North have failed. Please review your <a href=\"http://54.190.2.203/launcher\">planner</a> or email #{Parameter.get_string('smtp_email_address')} for more information.<br/><br/>
            #{
                ops.map { |op|
                    op.associations.map{|key, value| "<b>Operation ID:</b> #{op.id} <b>Operation Name:</b> #{op.name} <b>Plan:</b> #{op.plan.id} <b>Info:</b> #{key}, #{value}"}}.join("<br/>")
            }"
            if user.parameters.find { |p| p.key == 'email'}
                send_email user.name, user.parameters.find { |p| p.key == 'email'}.value, "DAMP Lab Job Failure Alert", body
            end
        end
    end
    
    #Takes an hash of file contents (already opened with File.read) with filenames as keys
    def send_email to_name, to_address, subject, body, file_paths={}
        if debug
            to_address = "nickemery23@gmail.com"
        end
        
        encoded_files = {}
        file_paths.each do |file_name, file_path|
            encoded_files[file_name] = [File.read(file_path)].pack("m")
        end
        
        marker = (Random.rand(1000000000) + 1000000000).to_s
        #Not using <<EOF because it messes up Aq text coloring
        msg_str =
        ["From: DAMP Lab North Aquarium <#{Parameter.get_string('smtp_email_address')}>",
        "To: #{to_name} <#{to_address}>",
        "Subject: #{subject}",
        "Mime-Version: 1.0",
        "Content-Type: multipart/alternative; boundary=#{marker}",
        "",
        "--#{marker}",
        "Content-Type: text/plain; charset=us-ascii",
        "",
        "...",
        "--#{marker}",
        "Content-Type: text/html",
        "Content-Transfer-Encoding:7bit",
        "Content-Disposition: inline",
        "",
        "<html>",
        "<body>",
        "#{body}<br/><br/>",
        "This is an automated email alert from the <a href=\"http://54.190.2.203\">DAMP Lab Aquarium system</a>.",
        "</body>",
        "</html>\n"].join("\n")
        if encoded_files.any?
            msg_str << "--#{marker}\n"
            msg_str << encoded_files.map{ |file_name, file_content|
                ["Content-Type: multipart/mixed; name = #{file_name};",
                "Content-Transfer-Encoding:base64",
                "Content-Disposition: attachment; filename = #{file_name}",
                "",
                "#{file_content}"].join("\n")
            }.join("--#{marker}\n")
        end
        msg_str << "--#{marker}--\n"
        smtp = Net::SMTP.new Parameter.get_string('smtp_email_server'), Parameter.get_float('smtp_email_port').round
        smtp.enable_starttls
        smtp.start('localhost', Parameter.get_string('smtp_email_address'), Parameter.get_string('smtp_email_password'), :login) do
            smtp.send_message(msg_str, Parameter.get_string('smtp_email_address'), to_address)
        end
    end
    
    #Methods in this module are added to the ShowBlock class directly, allowing them to be called inside a show block. Example:
    #show do
    #   title "Centrifuge the spin columns"
    #   centrifuge operations.running.count, 13000, 1
    #end
    module CloningMixin
        #Shows an image representing the correct centrifuge layout for n tubes in a 24 well centrifuge.
        #If n is 1 or 23, explains that a balance tube must be used. If n > 24, shows image for 24 tubes and image for remaining tubes (recursive).
        def centrifuge n, rpm, min
            @parts.push({check: "Centrifuge at #{rpm} RPM for #{min} #{'minute'.pluralize(min)}."})
            while n > 0
                if n == 1 || n == 23
                    @parts.push({check: "Create a balance tube of the same weight as the #{'tube'.pluralize(n)} you are spinning down."})
                    n += 1
                end
                if n >= 24
                    @parts.push({image: "#{Bioturk::Application.config.image_server_interface}centrifuge_layouts/24Tubes.png"})
                    n -= 24
                else
                    @parts.push({image: "#{Bioturk::Application.config.image_server_interface}centrifuge_layouts/#{n}Tubes.png"})
                    n = 0
                end
            end
        end
    end
    ShowBlock.class_eval { include CloningMixin }
end
