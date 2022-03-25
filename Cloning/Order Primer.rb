needs "Standard Libs/Ordering Lib"

class Protocol
  include Ordering
  require 'date'

  def main

    operations.retrieve.make
    
    show do
      title "Prepare to order primer"
      
      check "Go to the <a href='https://www.idtdna.com' target='_blank'>IDT website</a>, log in with the lab account. (Username: lortiz15)"
      warning "Ensure that you are logged in to this exact username and password!"
    end

    # make primer table
    tab = operations.map do |op|
      primer = op.output("Primer").sample
      ["Item ID: " + op.output("Primer").item.id.to_s + " " + primer.name, primer.properties["Overhang Sequence"] + primer.properties["Anneal Sequence"]]
    end
    
    # make lists of primers of different lengths
    operations.each { |op| op.temporary[:length] = (op.output("Primer").sample.properties["Overhang Sequence"] + op.output("Primer").sample.properties["Anneal Sequence"]).length }
    
    primers_over_60 = operations.select do |op| 
      length = op.temporary[:length]
      length > 60 && length <= 90
    end.map do |op|
        op.output("Primer").item
    end.to_sentence
    
    primers_over_90 = operations.select do |op| 
      length = op.temporary[:length]
      length > 90
    end.map do |op| 
        op.output("Primer").item
    end.to_sentence
    
    # show primer table
    show do
      title "Create an IDT DNA oligos order"
      check "Go to the <a href='https://www.idtdna.com/site/order/oligoentry'>oligo entry page</a>, click Bulk Input. Copy paste the following table and then click the Update button."
      
      table tab
      check "Scale for primer(s) #{primers_over_60} will have to be set to \"100 nmole DNA oligo.\"" if primers_over_60 != ""
      check "Scale amount for primer(s) #{primers_over_90} will have to be set to \"4 nmole Ultramer DNA Oligo.\"" if primers_over_90 != ""
    end
      
    data = show do
      title "Add to Order"
      
      check "Click Add to Order, review the shopping cart to double check that you entered correctly. There should be #{operations.length} primers in the cart."
      check "Select quote number 123830 and click apply."
      check "Click Checkout, then click Continue."
      
      get "number", var: "price", label: "Enter the total cost ($)", default: operations.running.count*4
      
      check "Enter the payment information: click on the oligo card tab, select the 816584606967 in Choose Payment and then click Submit Order."
      check "Click on Return Home, go to your <a href='https://www.idtdna.com/site/orderstatus/orderstatus'>order history</a> to find the Order Nbr (you may have to refresh the page a few times and wait 5-10 minutes before the order shows up)."
      
      warning "Do not forget to insert the order number before moving foward."
      
      get "text", var: "order_number", label: "Enter the IDT order number", default: 100
    end


    operations.each { |op| op.set_output_data("Primer", :order_number, data[:order_number]) }
    
    place_DNA_order ["IDT", data[:order_number], operations.running.count, data[:price].round(2), Date.today.strftime('%m/%d/%Y'), "Aquarium", "DLN"]
    
    return {}
    
  end

end
