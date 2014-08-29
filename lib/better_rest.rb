#!/usr/bin/env ruby

require 'sinatra'
require 'typhoeus'
require 'json'

set :public_dir, File.expand_path('../../public', __FILE__)
set :views, File.expand_path('../../views', __FILE__)

helpers do
  include Rack::Utils
  alias_method :h, :escape_html
end

BETTER_SIGNATURE = "BetteR - https://github.com/at1as/BetteR"

get '/?' do
  @requests = ["GET","POST","PUT","DELETE","HEAD","OPTIONS","PATCH"]
  @times = ["1", "2", "5", "10"]
  @timeout = ["1","2","5","10","60"]
  @validHeaderCount = 1
  @headerHash = {"" => ""}
  @follow, @verbose, @ssl, @loggingOn = true, true, false, false
  @visible = ["displayed", "hidden", "displayed", "displayed", "displayed"]	#Ordered display toggle for frontend: REQUEST, AUTH, HEADERS, PAYLOAD, RESULTS

  erb :index
end

post '/' do
  @headerHash = {}
  @validHeaderCount = 1
  @formResponse = true
  @follow, @verbose, @ssl, @loggingOn = true, true, false, false
  @requestBody = ""
  @visible = [:servURLDiv, :servAuthDiv, :servHeaderDiv, :servePayloadDiv, :servResultsDiv].map{ |k| params[k] }
  @var_key = params[:varKey]
  @var_value = params[:varValue]

  # Loop through Header key/value pairs
  # If a header is created and deleted in the UI before submit, headerCount will not renormalize (and will exceed the number headers sent)
  # This will check that a particular header exists, before adding it to the Hash
  params[:headerCount].to_i.times do |i|
    @keyIncrement = "key#{i}"
    @valueIncrement = "value#{i}"

    if !(params.fetch(@keyIncrement, '').empty? || params.fetch(@valueIncrement, '').empty?)
      @headerHash[params[@keyIncrement]] = params[@valueIncrement]
      @validHeaderCount += 1
    end
  end

  # Shameless branding. Only if User-Agent isn't user specified
  @headerHash["User-Agent"] ||= BETTER_SIGNATURE

  # Check which options the user set or default to the following
  @follow = false if params[:followlocation] == ""
  @verbose = false if params[:verbose] == ""
  @ssl = true if params[:ssl_verifypeer] == "on"
  @loggingOn = true if params[:enableLogging] == "on"

  # Assemble the Payload
  if params[:datafile]
    @requestBody = { content: params[:payload], file: File.open(params[:datafile][:tempfile], 'r') }
  else
    @requestBody = { content: params[:payload] }
    #@requestBody = { content: JSON.parse(params[:payload]) } #.gsub(':', '=>')[1..-2].to_json#[1..-2]
  end

  # For parallel Requests
  hydra = Typhoeus::Hydra.new

  # Create the Request (swap variable keys for values, if they have been set)
  request = Typhoeus::Request.new(
    params[:url].gsub("{{#{@var_key}}}", @var_value),
    method: params[:requestType],
    username: params[:usr].gsub("{{#{@var_key}}}", @var_value),
    password: params[:pwd].gsub("{{#{@var_key}}}", @var_value),
    auth_method: :auto,		#Should ideally not be auto, in order to test unideal APIs
    headers: @headerHash,
    body: @requestBody,
    followlocation: @follow,
    verbose: @verbose,
    ssl_verifypeer: @ssl,
    timeout: Integer(params[:timeoutInterval])
  )

  # Substitute Header Values for defined variables
  request.options[:headers].each do |key, val|
    if val.to_s.include? "{{#{@var_key}}}"
      request.options[:headers][key.to_s] = val.gsub("{{#{@var_key}}}", @var_value)
    end
  end

  # Remove unused fields from request (some APIs don't handle unexpected fields)
  request.options.delete(:body) if @requestBody[:content] == "" unless @requestBody[:file]
  request.options.delete(:username) if params[:usr] == ""
  request.options.delete(:password) if params[:pwd] == ""

  # Send the request (specified number of times)
  params[:times].to_i.times.map{ hydra.queue(request) }
  hydra.run
  response = request.response

  # If user-agent wasn't set by user, don't bother showing the user this default
  request.options[:headers].delete('User-Agent') && @headerHash.delete("User-Agent") if @headerHash["User-Agent"] == BETTER_SIGNATURE

  # Log the request response
  if @loggingOn
    File.open('log/' + Time.now.strftime("%Y-%m-%d") + '.log', 'a') do |file|
      file.write("-" * 10 + "\n" + Time.now.to_s + request.inspect + "\n\n" )
    end
  end

  # These values will be used by the ERB page
  # Add the URL to the Request Options returned
  request.options[:url] = request.url
  @requestOptions = JSON.pretty_generate(request.options)
  @returnBody = response.body
  @returnCode = response.return_code
  @returnTime = response.time
  @statCodeReturn = response.response_headers
  @requests = ["#{params[:requestType]}", "GET","POST","PUT","DELETE","HEAD","OPTIONS","PATCH"].uniq
  @times = ["#{params[:times]}", "1", "2", "5", "10"].uniq
  @timeout = ["1","2","5","10","60"]

  erb :index
end

not_found do
  redirect '/'
end

# Returns Ruby/Sinatra Environment details
get '/env' do
  <<-ENDRESPONSE
      Ruby:    #{RUBY_VERSION} <br/>
      Rack:    #{Rack::VERSION} <br/>
      Sinatra: #{Sinatra::VERSION}
  ENDRESPONSE
end

# Kills process. Work around for Vegas Gem not catching SIGINT from Terminal
get '/quit' do
  puts "\nExiting..."
  exit!
end
