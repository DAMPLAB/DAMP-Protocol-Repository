needs "Standard Libs/Debug Lib"
class Protocol 
  include Debug
  def main
    
    #The actual protocol doesn't do much here. See the precondition code. This operation type will be "waiting" until the user has added the special association "sequencing_ok" or the special association "delete_requested"
    show do
        title "Click OK"
        note "Click OK."
        note "No technician action is required. This operation type serves as a checkpoint."
    end
    
    operations.each do |op|
        if Random.rand > 0.4
            op.input("Plasmid").item.associate(:delete_requested, "delete requested").save
        end
        if Random.rand > 0.4
            op.input("Plasmid").item.mark_as_deleted
        end
        if Random.rand > 0.25
            op.input("Plasmid").item.associate(:from_culture, (Random.rand*1000).round).save
        end
    end if debug
    
    #pass through plasmid and error op if the user has requested that the input item should be deleted
    operations.each do |op| 
        op.pass("Plasmid","Plasmid")
        if !op.input("Plasmid").item.get(:delete_requested).nil?
            op.error :incorrect_seq_results, "Automatically cancelled due to incorrect sequencing results."
            if op.input("Plasmid").item.get(:from_culture)
                ot_id = ObjectType.select{|ot| ot.name == "Plasmid Glycerol Stock"}.first.id
                gstocks = Item.where(object_type_id: ot_id)
                gstocks.each do |gstock|
                    gstock.associate(:from_culture, op.input("Plasmid").item.get(:from_culture)).save if (debug && Random.rand > 0.95)
                    if gstock.get(:from_culture) && gstock.get(:from_culture).to_s == op.input("Plasmid").item.get(:from_culture).to_s
                        gstock.associate(:delete_requested, "A plasmid from the same culture was sequenced and found to be incorrect, this item has been automatically marked for disposal.").save
                    end
                end
            end
        end
    end
    
    return {}
  end
end
