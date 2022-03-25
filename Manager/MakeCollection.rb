# This is a default, one-size-fits all protocol that shows how you can 
# access the inputs and outputs of the operations associated with a job.
# Add specific instructions for this protocol!

class Protocol

  def main
      
    op = operations.first
    operations.make    
    op.output("Batch").item.mark_as_deleted
    
    item_info = show do
        title "What type of Collection do you want to create?"
        note "object type name must be exactly correct"
        
        get "text", var: "object_type", label: "Object type", default: "Stripwell"
        get "text", var: "location", label: "Location", default: "Bench"
    end
     
    object_type = ObjectType.find_by_name(item_info[:object_type])
    new_item = produce new_collection object_type.name
    
    op.output("Batch").set item: new_item

    show do
        title "Colleciton Created!"
        
        note "Made new #{op.output("Batch").item.object_type.name}"
        note "Collection link #{op.output("Batch").item}"
        note "Now we will populate the collection with samples of your choice"
    end
    
    
    coll = op.output("Batch").collection
    coll.location = item_info[:location]
    continue = true
    while continue
        add = show do 
            title "how many samples to add to #{coll.id}"
            
            
            get "number", var: "sample", label: "Sample id to add", default: 7
            get "number", var: "add", label: "how many to add", default: 0
            select ["Yes", "No"], var: "continue", label: "I want to add a different sample as well", default: 1
        end        
        
        sample = Sample.find(add[:sample])
        
        add[:add].times do
            coll.add_one sample
        end
        continue = add[:continue] == "Yes"
    end
    
    show do 
        title "Collection finsished and ready to use"
        
        note "Use the \'edit collection\' protocol to add or remove samples"
        table coll.matrix
    end
    
    
    
    operations.store
    
    return {}
    
  end

end
