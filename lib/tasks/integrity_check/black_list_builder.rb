class BlackListBuilder
  
  BatchBook::boot
  #Define required tags inside an array case a record may have either one.
  #IE: A contact may be either a lead or a customer
  TAGS_REQUIRED = {:contacts => [['lead', 'customer']], 
                   :deals => []
                   }
  TAGS_ALLOWED = {:contacts => ['ucemployee'], 
                  :deals => []
                  }
  SUPERTAGS_REQUIRED = {:contacts => ['ownership', 'source'], 
                        :deals => ['dealinfo']
                        }
  
  def initialize(type, path)
    @type = type           
    @path = path
    @black_list = BlackList.new
    @white_list = []
    @tags_required = TAGS_REQUIRED[@type]
    @tags_allowed = TAGS_ALLOWED[@type]
    @supertags_required = SUPERTAGS_REQUIRED[@type]
    @collection = case @type
      when :contacts
        Person.all(:disable_caching => true) | Company.all(:disable_caching => true)
      when :deals
        Deal.all(:disable_caching => true)
      when :todos
        Todo.all(:disable_caching => true)
      when :communications
        Communication.all(:disable_caching => true)
      else
        []
    end
  end
  
  def generate_report
    #Hack for deals
    @black_list.items.delete_if{|i| i.record.status == '100%' || i.record.status == 'lost'} if @type == :deals
    @white_list.each {|allowed_item| @black_list.items.delete_if{|i| i.record == allowed_item}}
    File.open("#{@path}/#{@type.to_s}.html", "w") do |file|
      file << %Q{
      <style>body,th{text-align:center}table{width:50%;margin-left:350px}</style>
      <html><body><h1>Report on Integrity Check for #{@type.to_s.titleize}</h1>
      <h2>Created at #{Time.now}</h2>
      <h3>Total number of records: #{@collection.size}</h3>
      <h3>Total number of failing records: #{@black_list.items.size}</h3>
      <table border=1>
      <tr>
        <th>Record</th>
        <th>Invalidation Reason</th>
      </tr>
      }
      @black_list.items.each do |invalid_item|
        file << %Q{
        <tr>
          <td><a href='https://#{BatchBook.account}.batchbook.com/#{@type.to_s}/show/#{invalid_item.record.id}'>#{invalid_item.record.name}</a></td>
          <td>
            <ul>
            #{invalid_item.reasons.map{|reason| "<li>#{reason}</li>"}.join("\n")}
            </ul>
          </td>
        </tr>
        }
      end
      file << "</table></body></html>"
    end
  end
  
  def check_tags
    @collection.each do |item|
      attr = item.attributes['tags']
      tags = attr.blank? ? [] : attr.map{|a| a.attributes['name'] if a.attributes['supertag'] == 'false'}
      decoy = @tags_required.clone
      @white_list << item unless (tags & @tags_allowed).blank?
      conditional_tags = decoy.find_all{|tag| tag.is_a?(Array)} 
      conditional_tags.each do |tag_collection|
        if (tags & tag_collection).blank?
          @black_list.add item, "Does not have one of these tags: #{tag_collection.join(',')}."
        end
      end
      decoy.delete_if{|tag| tag.is_a?(Array)}
      comparison = tags & decoy
      if !decoy.blank? && comparison != decoy
        missing = comparison.blank? ? decoy : decoy - comparison
        @black_list.add item, "Does not have these tags: #{missing.uniq.join(',')}."
      end
    end
  end
  
  def check_supertags
    @collection.each do |item|
      attr = item.attributes['tags']
      tags = attr.blank? ? [] : attr.map{|a| a.attributes['name'] if a.attributes['supertag'] == 'true'}
      supertags = attr.find_all{|a| a.attributes['supertag'] == 'true'}
      missing = []
      unless supertags.blank?
        @supertags_required.each do |supertag|
          temp = supertags.find{|e| e.name == supertag}
          missing << supertag if temp.blank? || temp.fields.blank?
        end
        unless missing.blank?
          @black_list.add item, "Does not have these supertags: #{missing.uniq.join(',')}."
        end
      else
        @black_list.add item, "Does not have these supertags: #{@supertags_required.join(',')}."
      end 
    end
  end
  
  def check_todos
    todos = Todo.find(:all) || []
    @collection.each do |item|
      unless todos.find{|todo| todo.title == item.title}
        @black_list.add item, "Does not have a corresponding To-Do."
      end
    end
  end
  
  def check_status
    @collection.each do |item|
      if item.status.blank?
        @black_list.add item, "Does not have a status defined."
      end
    end
  end
  
end