needs "Standard Libs/Debug Lib"
needs "Cloning Libs/Cloning"

# TO DO:
    # Create option for "there are baby colonies but they're not big enough for protocols" case--put back in incubator
    # Re-streak the plate if there's too much contamination--fire check plate again in 24 hrs, probably collection

class Protocol
  include Debug
  include Cloning
  
  def main
    operations.sort_by! {|op| op.input("Plate").item.id}
    # Take plates
    operations.retrieve
    
    # Count the number of colonies
    info = get_colony_numbers
    
    # Update plate data
    update_item_data info
    
    # Delete and discard any plates that have 0 colonies
    discard_bad_plates if operations.any? { |op| op.temporary[:delete] }
    
    return {} if check_for_errors
    
    # Parafilm and label plates
    parafilm_and_store
    
    return {}
  end
  
  
  
  # Count the number of colonies and select whether the growth is normal, contaminated, or a lawn
  def get_colony_numbers
    show do
      title "Estimate colony numbers"
      
      operations.each do |op|
        plate = op.input("Plate").item
        get "number", var: "n_white#{plate.id}", label: "Estimate how many white colonies are on #{plate}", default: 0
        get "number", var: "n_blue#{plate.id}", label: "Estimate how many blue colonies are on #{plate}", default: 0
        get "number", var: "n_red#{plate.id}", label: "Estimate how many red colonies are on #{plate}", default: 0
        select ["normal", "contamination", "lawn"], var: "s#{plate.id}", label: "Choose whether there is contamination, a lawn, or whether it's normal.", default: 0
      end
    end
  end
  
  # Alter data of the virtual item to represent its actual state
  def update_item_data info
    operations.each do |op|
      plate = op.input("Plate").item
      log_info "", info["n_white#{plate.id}".to_sym]
      log_info "", info["n_red#{plate.id}".to_sym]
      log_info "", info["n_blue#{plate.id}".to_sym]
      if (info["s#{plate.id}".to_sym] == "normal") && (info["n_white#{plate.id}".to_sym] == 0) && (info["n_blue#{plate.id}".to_sym] == 0) && (info["n_red#{plate.id}".to_sym] == 0)
        plate.mark_as_deleted
        plate.save
        op.temporary[:delete] = true
        op.error :no_colonies, "There are no colonies for plate #{plate.id}"
      else
        plate.associate :white_colonies, info["n_white#{plate.id}".to_sym]
        plate.associate :blue_colonies, info["n_blue#{plate.id}".to_sym] if !(info["n_blue#{plate.id}".to_sym] == 0)
        plate.associate :red_colonies, info["n_red#{plate.id}".to_sym] if !(info["n_red#{plate.id}".to_sym] == 0)
        plate.associate :status, info["s#{plate.id}".to_sym]
        checked_ot = ObjectType.find_by_name("Checked E coli Plate of Plasmid")
        plate.object_type_id = checked_ot.id
        plate.object_type = checked_ot
        plate.save
        op.pass("Plate","Plate")
      end
    end
  end
  
  # discard any plates that have 0 colonies
  def discard_bad_plates
      show do
        title "Discard Plates"
        discard_plate_ids = operations.select { |op| op.temporary[:delete] }.map { |op| op.input("Plate").item.id }
        note "Discard the following plates with 0 colonies: #{discard_plate_ids.to_sentence}"
    end
  end
  
  
  # Parafilm and label any plates that have suitable growth
  def parafilm_and_store
    plates_to_parafilm = operations.reject{|op| op.temporary[:delete] }.map{|op| op.input("Plate").item}
    show do
      title "Label and Parafilm"
      check "Confirm that plates #{plates_to_parafilm.map{ |i| i.id }.to_sentence} are labelled with their item ID numbers on the side (outside edge of plate) and the bottom of the plate."
      check "Confirm that plates are labelled with the proper storage location on the side (outside edge of plate) and the bottom of the plate, and parafilm each one."
      warning "The location will appear on the next page."
    end
    
    #Put plates back under control of wizard (were in incubator)
    plates_to_parafilm.each do |i|
        wiz = Wizard.find_by_name(i.object_type.prefix)
        i.move wiz.int_to_location(wiz.next.number)
        wiz.save
        i.save
    end

    release plates_to_parafilm, interactive: true
  end
end

