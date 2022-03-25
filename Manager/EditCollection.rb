class Protocol
  def main
    operations.retrieve
    operations.each do |op|
        item_id = op.input("Item ID").val.to_i
        col = Collection.find item_id
        take [col]
        
        # remove samples
        subt = show do 
            title "how many samples to remove from #{col.id}"
            
            get "number", var: "subt", label: "how many to remove", default: 0
            get "number", var: "sample", label: "Sample ID to remove", default: 0
        end
        if !subt[:subt].nil? && !subt[:sample].nil?
            sample = Sample.find subt[:sample]
            subt[:subt].times do 
                col.remove_one sample
            end
        end
        
        # add samples
        add = show do 
            title "how many samples to add to #{col.id}"
            
            get "number", var: "add", label: "how many to add", default: 0
            get "number", var: "sample", label: "Sample ID to add", default: 0
        end        
        if !add[:add].nil? && !add[:sample].nil?
            sample = Sample.find add[:sample]
            add[:add].times do
                col.add_one sample
            end
        end
         
        release [col]
    end
    return {}
  end
end
