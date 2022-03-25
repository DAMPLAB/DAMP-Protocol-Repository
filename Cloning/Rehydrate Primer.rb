needs "Cloning Libs/Cloning"
needs "Standard Libs/Debug Lib"
needs "Cloning Libs/OpenTronsAq"

class Protocol
  include Cloning
  include Debug
  include OpenTronsAq
  
  #Item.extend(ItemMixin)
  
  def main
    current_taken_items = []
    output_volumes = {"Primer Stock" => 190}

    operations.sort_by! {|op| op.input("Primer").item.id}
    
    robust_make ["Primer Stock"], current_taken_items
    
    operations.each do |op|
        op.input("Primer").item.associate(:order_number, (Random.rand*10000).round).save
    end if debug
    
    order_nums = operations.map{|op| op.input("Primer").item.get(:order_number)}.uniq.to_sentence
    
    show do
        title "Find primers at bench"
        check "Find primers #{operations.running.map{|op| op.input("Primer").item}.to_sentence} on the bench (look for packages with order numbers: #{order_nums})"
    end
    
    robust_take_inputs ["Primer"], current_taken_items, interactive: false
    
    show do
      title "Enter the nmol of the primer"
      check "Enter the amount of each primer supplied by IDT in nanomoles. This is written toward the bottom of the tube. The id of the primer is listed before the primer's name on the side of the tube."
      table operations.start_table
        .input_item("Primer")
        .get(:nmol, type: "number", heading: "nmol", default: 25)
        .end_table
      check "Get out #{operations.running.count} new 1.5 ml tubes with the following IDs: #{(operations.map {|op| op.output("Primer Stock").item.id}).to_sentence}"
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
        
        p300 = prot.instruments.P300_Single(mount: 'left', tip_model: "tiprack-200ul")
        
        prot.assign_wells operations.map{|op| op.input("Primer").item}
        
        prot.assign_wells operations.map{|op| op.output("Primer Stock").item}
        
        operations.each do |op|
            p300.pick_up_tip
            p300.aspirate(200, prot.find_well(water).bottom(1))
            p300.dispense(200, prot.find_well(op.input("Primer").item).bottom(1))
            8.times do
                p300.aspirate(150, prot.find_well(op.input("Primer").item).bottom(2))
                p300.dispense(150, prot.find_well(op.input("Primer").item).bottom(2))
            end
            p300.aspirate(180, prot.find_well(op.input("Primer").item).bottom(1))
            p300.dispense(180, prot.find_well(op.output("Primer Stock").item).bottom(1))
            p300.drop_tip
        end
        
        operations.each do |op|
            target_vol = (op.output("Primer Stock").object_type.data_object[:rec_conc] / (op.temporary[:nmol] / 200000.0)) * 180
            vol_to_add = ([target_vol, 1400].min - 180).to_i
            p300.pick_up_tip
            (vol_to_add / 200).times do
                p300.aspirate(200, prot.find_well(water).bottom(1))
                p300.dispense(200, prot.find_well(op.output("Primer Stock").item).top(0))
            end
            p300.aspirate(vol_to_add % 200, prot.find_well(water).bottom(1))
            p300.dispense(vol_to_add % 200, prot.find_well(op.output("Primer Stock").item).top(0))
            p300.drop_tip
        end
        
        run_protocol prot
        
        show do
            title "Clean up"
            check "Discard empty original tubes."
            check "Cap all 1.5 mL tubes."
        end
        
        operations.running.each do |op|
            op.output("Primer Stock").item.associate :concentration, op.output("Primer Stock").object_type.data_object[:rec_conc]
            #op.output("Primer Stock").item.associate :volum, output_volumes["Primer Stock"]
            op.output("Primer Stock").item.save
            op.input("Primer").item.mark_as_deleted
        end
        
    else
        
        show do
          title "Add water and mix"
          warning "Be sure to spin down the primer tubes before opening!"
          check "Add 200 µl of water to all primer tubes."
          check "Wait one minute for the primer to dissolve."
          check "Vortex tubes for 2 seconds."
          check "Spin down tubes for 2 seconds"
        end
        
        show do
            title "Transfer to new tubes"
            note "Transfer diluted primers to #{operations.running.count} new 1.5 ml tubes with the following IDs:"
            table operations.start_table
            .output_item("Primer Stock")
            .custom_column(heading: "Original primer tube from IDT") { |op| {content: "190 µl of #{op.input("Primer").item.id}", check: true}}
            .end_table
        end
        
        operations.running.each do |op|
            op.output("Primer Stock").item.associate :concentration, op.temporary[:nmol]/200000.0
            #op.output("Primer Stock").item.associate :volum, output_volumes["Primer Stock"]
            op.output("Primer Stock").item.save
            op.input("Primer").item.mark_as_deleted
        end
        
        #items_to_dilute = operations.running.map{|op| op.output("Primer Stock").item}
    end
    
    #show do
    #    title "Dilute the following items"
    #    check "Dilute items according to the following table:"
    #    table_matrix = Array.new(items_to_dilute.count+1) {Array.new}
    #    table_matrix[0] = ["Item ID", "Water to add"]
    #    items_to_dilute.each_with_index do |item, item_index|
    #        dilution_factor = item.get(:concentration).to_f / item.object_type.data_object[:rec_conc].to_f
    #        volume_to_add = ((dilution_factor - 1.0)*item.get(:raw_volume).to_f).round(2)
    #        new_volume = ((item.get(:raw_volume).to_f+volume_to_add)*0.95-2.0).round(2)
    #        item.associate(:volume, new_volume)
    #        item.associate(:raw_volume, nil)
    #        item.associate(:concentration, item.object_type.data_object[:rec_conc].to_f)
    #        item.associate(:concentration_keyword, "STANDARD")
    #        item.save
    #        table_matrix[item_index+1] = [item.id.to_s, {content: "#{volume_to_add} µl of water", check: true}]
    #    end
    #    table table_matrix
    #end
    
    
    #operations.running.store io: "output", interactive: true
    
    store_outputs_with_volumes output_volumes, current_taken_items, interactive: true
    
    return {}
    
  end

end
