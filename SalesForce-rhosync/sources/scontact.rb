require 'json'
require 'rest_client'

class Scontact < SourceAdapter
  def initialize(source,credential)
    super(source,credential)
  end
 
  def login
    puts "LOGIN USER: #{current_user.login}"
    @sessionid = Store.get_value("#{current_user.login}:session")
    endpoint_url = Store.get_value("#{current_user.login}:endpoint_url")

    @resturl = endpoint_url + "/services/data/v20.0"
    @restheaders = {
      "Accept" => "*/*", 
      "Authorization" => "OAuth #{@sessionid.split('!')[1]}", 
      "X-PrettyPrint" => "1"
    }
    
    @postheaders = {
      "Accept" => "*/*", 
      "Content-Type" => "application/json", 
      "Authorization" => "OAuth #{@sessionid.split('!')[1]}", 
      "X-PrettyPrint" => "1"
    }
    
    @fields = []
    parsed=
    JSON.parse(
      RestClient.get(
        "#{@resturl}/sobjects/Contact/describe/", 
        @restheaders
      ).body
    )
    
    parsed["fields"].each do |field|
      @fields << field
    end

  end

  def metadata
    show = []
    data = {}
    @fields.each do |f|


      key = "" + f["name"]
      key[0] = key[0,1].downcase
      key = "object" if key == "id"

      data[key] = f

      field = {}
      xtype = "textfield"
      type = "textfield"
      selectoptions = []
      
      if f["type"] == "reference"
        type = 'reference'
        f["label"].gsub!(/ ID/,"")
      elsif f["type"] == "id"
        type = 'hiddenfield'
      elsif f["type"] == "picklist"
        type = 'selectfield'
        selectoptions << {:text => "", :value => ""}
        f["picklistValues"].each do |v|
          option = {}
          option[:text] = v["label"]
          option[:value] = v["value"]
          selectoptions << option
        end
      elsif f["type"] == "boolean"
        #sencha toggle broken, textfield for now
        type = 'boolfield'
      elsif f["type"] == "textarea"
        type = 'textarea'
      elsif f["type"] == "email"
        type = 'textfield'
      elsif f["type"] == "date"
        type = 'textfield'
      end
              
      
      if not f["updateable"] and type == 'textfield' 
        type = 'readonlytext'
      end
      
      field = {
        :xtype => xtype,
        :label => f["label"],
        :name => "#{key}",
        :type => type,
        :fieldtype => f["type"],
        :linkto => f["referenceTo"][0],
        :value => "{{@crmobject/#{key}}}"
      }
      
      field[:options] = selectoptions.to_json if type == 'selectfield'
      
      show << field
    end

    {'showfields' => {:type => 'form', :children => show}, 'datafields' => data}.to_json
  end

  def query(params=nil)

    @result = {}

    fieldquery = ""
    @fields.each do |f|
      fieldquery << ",#{f["name"]}"
    end
    fieldquery[0] = " "

    querystr = "SELECT #{fieldquery} from Contact"

    requesturl = @resturl + "/query/?q=" + CGI::escape(querystr)

    raw_data = RestClient.get(requesturl, @restheaders) do |response,request, result, &block| 
      case response.code 
      when 200 
        p "It worked !" 
        response.body
      when 400
        p "It failed !"
        p response.body
        raise "400 error"
      end
    end

    parsed_data = JSON.parse raw_data

    parsed_data["records"].each do |a|
      @result[a["Id"]] = {}
      @fields.each do |f|
        key = "" + f["name"]
        key[0] = key[0,1].downcase
        @result[a["Id"]][key] = a[f["name"]]
      end
    end

  end
  
  def sync
    # Manipulate @result before it is saved, or save it 
    # yourself using the Rhosync::Store interface.
    # By default, super is called below which simply saves @result
    super
  end
 
  def create(create_hash,blob=nil)
    fhash = {}
    @fields.each do |f|
      fhash[f["name"].downcase] = f
    end
    
    # Re-upcase the first character, and save to our submit_hash only if the field is marked creatable
    submit_hash = {}
    create_hash.each do |k,v|
      nk = k.dup
      nk[0] = k[0,1].upcase
      submit_hash[nk] = v if fhash[k.downcase]["createable"] and v != "" and fhash[k.downcase]["type"] != "reference" and v != "Invalid Date"
    end
    
    requesturl = "#{@resturl}/sobjects/Contact/"
    
    begin
      RestClient.post(requesturl, submit_hash.to_json, @postheaders)
    rescue Exception => e
      puts "POST ERROR"
      puts e.inspect
      puts e.backtrace.join("\n")
    end
    
    ""
  end
 
  def update(update_hash)
    # Make hash out of field array, so we can use name as an index
    fhash = {}
    @fields.each do |f|
      fhash[f["name"].downcase] = f
    end

    # Re-upcase the first character, and save to our submit_hash only if the field is marked updateable
    submit_hash = {}
    update_hash.each do |k,v|
      nk = k.dup
      nk[0] = k[0,1].upcase
      submit_hash[nk] = v if fhash[k.downcase]["updateable"] and v != "" and fhash[k.downcase]["type"] != "reference" and v != "Invalid Date"
    end

    update_id = update_hash['id']

    requesturl = @resturl + "/sobjects/Contact/#{update_id}?_HttpMethod=PATCH"

    begin
      RestClient.post(requesturl, submit_hash.to_json, @postheaders)
    rescue Exception => e
      puts "POST ERROR"
      puts e.inspect
      puts e.backtrace.join("\n")
    end
    
  end
 
  def delete(delete_hash)
    requesturl = @resturl + "/sobjects/Contact/#{delete_hash["id"]}?_HttpMethod=DELETE"

    begin
      RestClient.post(requesturl, "", @postheaders)
    rescue Exception => e
      puts "POST ERROR"
      puts e.inspect
      puts e.backtrace.join("\n")
    end
  end
 
  def logoff
    # TODO: Logout from the data source if necessary
  end
end