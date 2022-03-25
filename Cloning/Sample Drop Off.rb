needs "Cloning Libs/Cloning"
needs "Standard Libs/Debug Lib"

class Protocol
  include Cloning
  include Debug
  
  def main
    
    current_taken_items = []
    robust_make ["Sample being dropped off"], current_taken_items
    
    table_matrix = Array.new (operations.running.count + 1) {Array.new}
    table_matrix[0] = ["New label (item ID)", "Label on user-supplied item (erase this)"]
    operations.running.map{|op| op.output_array("Sample being dropped off").items}.flatten.each_with_index{ |item, index| table_matrix[index+1] = [item.id.to_s, {content: ("#{item.sample.id.to_s} (#{item.sample.name})"), check: true}]}
    
    #Manually entering primer stock concentrations supplied by user (because these are written on tops of tubes and will be destroyed by relabelling)
    primer_stocks = operations.select{|op| op.output_array("Sample being dropped off")[0].object_type.name == "Primer Stock"}.map{|op| op.output_array("Sample being dropped off").items}.flatten
    
    conc_data = show do
      title "Please determine and enter concentrations of the following items in µM."
      note "Please determine and enter concentrations of the following items in µM."
      warning "Do not enter concentration in ng/ul or any unit other than µM."
      primer_stocks.each do |i|
        get "number", var: "c#{i.id}", label: "#{i.sample.id.to_s} (#{i.sample.name})", default:  (debug ? Random.rand*100 : 0)
      end
    end if primer_stocks.any?
    
    primer_stocks.each do |item|
        item.associate(:concentration, conc_data["c#{item.id}".to_sym] / 1000000.0)
        item.save
    end if primer_stocks.any?
    
    show do
        title "Relabel items from user"
        check "Users supply samples labelled with sample IDs and/or sample names instead of item IDs. You must relabel these items before adding them to the inventory (transfer to new containers if necessary)."
        table table_matrix
    end
    
    characterize current_taken_items, current_taken_items
    
    robust_release current_taken_items, current_taken_items, interactive: true
    
    return {}
    
  end
  
end
