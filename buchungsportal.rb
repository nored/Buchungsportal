#!/usr/bin/env ruby
# coding: utf-8
#encoding: utf-8
require "rubygems"
require "sinatra/base"
require 'yaml/store'
require 'sinatra/flash'
require 'sinatra/cookies'
require 'securerandom'
require 'sinatra/form_helpers'
require 'sinatra/session'
require 'mail'
require 'erb'
require 'csv'

class Buchungsportal < Sinatra::Base
  helpers Sinatra::Cookies
  helpers Sinatra::FormHelpers
  enable :sessions
  register Sinatra::Flash
  set :protection, :except => :frame_options
  set :cookie_options, :domain => nil
  register Sinatra::Session
  set :session_secret, ENV['PASSWORDHASH']
  use Rack::Session::Cookie, :key => 'rack.session',
  #                          :domain => ENV['DOMAIN'],
                            :path => '/',
                            :expire_after => 2000, # In seconds
                            :secret => ENV['PASSWORDHASH']

  Spots = {
    '1' => 'c',
    '2' => 'c',
    '3' => 'c',
    '4' => 'c',
    '5' => 'c',
    '6' => 'c',
    '7' => 'd',
    '8' => 'd',
    '9' => 'd',
    '10' => 'd',
    '11' => 'c',
    '12' => 'd',
    '13' => 'd',
    '14' => 'd',
    '15' => 'd',
    '16' => 'd',
    '17' => 'd',
    '18' => 'd',
    '19' => 'd',
    '20' => 'c',
    '21' => 'c',
    '22' => 'd',
    '23' => 'd',
    '24' => 'd',
    '25' => 'd',
    '26' => 'c',
    '27' => 'c',
    '28' => 'c',
    '29' => 'c',
    '30' => 'c',
    '31' => 'c',
    '32' => 'c',
    '33' => 'c',
  }

  Participants = {}
  Timestamps = {}
  TableHeader = [
    "Unternehmen",
    "Straße / Nr.",
    "PLZ",
    "Ort",
    "Ansprechpartner Anrede",
    "Ansprechpartner Titel",
    "Ansprechpartner Vorname",
    "Ansprechpartner Nachname",
    "Ansprechpartner Abteilung",
    "Ansprechpartner Telefon",
    "Ansprechpartner Fax",
    "Ansprechpartner E-Mail-Adresse",
    "Unternehmensvertreter Anrede",
    "Unternehmensvertreter Titel",
    "Unternehmensvertreter Vorname",
    "Unternehmensvertreter Nachname",
    "Anzahl vor Ort",
    "Leistungspaket",
    "Stellplatzreservierung",
    "Werbeanzeige im Messekatalog",
    "Logo im Messekatalog",
    "Einladung in 2020",
    "Stellplatz",
    "Buchungsdatum",
    "Zielgruppe",
    "AGB"
  ]
  helpers do
    def createDB()
      if !(File.file?("spots.yml")) 
        @store = YAML::Store.new 'spots.yml'
        @store.transaction do
          @store['spots'] ||= Spots
          @store['participants'] ||= Participants
          @store['timestamps'] ||= Timestamps
        end
      end
    end
    def getSpotsFromDB()
      @store = YAML::Store.new 'spots.yml'
      @spots = @store.transaction { @store['spots'] }
    end
    def getParticipantsFromDB()
      @store = YAML::Store.new 'spots.yml'
      @participants = @store.transaction { @store['participants'] }
    end
    def setTimeStamp(id)
      @store = YAML::Store.new 'spots.yml'
      oldTransactions = @store.transaction { @store['timestamps'] }.nil? ? Timestamps : @store.transaction { @store['timestamps'] }
      @store.transaction do
        @store['timestamps'][id] = Time.now
      end
    end
    def removeUnintentionalBookings(id)
      if (!id.nil?)
        @store = YAML::Store.new 'spots.yml'  
        participants = @store.transaction { @store['participants'] }
        if (!participants.values.include?(id))
          @store.transaction do
            @store['spots'][id] = Spots[id]
          end
        end
      end
    end
    def removeMultiBookings(id)
      @store = YAML::Store.new 'spots.yml'  
      @spots = @store.transaction { @store['spots'] }
      if @spots.values.include?(id)
        old_Spots = @spots.select {|k,v| v == id}
        old_Spots.keys.each do |k| 
          @store.transaction do
            @store['spots'][k] = Spots[k]
          end
        end
      end
    end
    def bookSpot(id, sessionID)
      @store = YAML::Store.new 'spots.yml'
      @store.transaction do
        @store['spots'][id] = sessionID
      end
    end
    def saveParticipant(data)
      @store = YAML::Store.new 'spots.yml'
      @store.transaction do
        @store['participants'][data["sessionID"]] = data
      end
    end
    def compileBody(params)
      @params = params
      mail = ERB.new(File.read('./views/mail.erb').force_encoding("UTF-8")).result(binding)
    end
    def writeMail(recipients, params)
      compileBody(params)
      user = ENV['MAILUSER']
      pass = ENV['MAILPASSWORD']
      mail = ERB.new(File.read('./views/mail.erb').force_encoding("UTF-8")).result(binding)
      options = { 
        :address              => "mail.th-brandenburg.de",
        :port                 => 25,
        :user_name            => user,
        :password             => pass,
        :authentication       => 'plain',
        :enable_starttls_auto => true  }
      # Set mail defaults
      Mail.defaults do
        delivery_method :smtp, options
      end
      recipients.each do |m|
        Mail.deliver do
          to "#{m}"
          from "#{ENV['MAIL2']}"
          subject "Buchungsbestätigung Firmenkontaktmesse 2020"
          content_type 'text/html; charset=UTF-8'
          body "#{mail}"
        end
      end
    end
    def deletebooking(spotID, userID, userSessionID)
      @store = YAML::Store.new 'spots.yml'
      getParticipantsFromDB()
      getSpotsFromDB()
      @spots.delete(spotID)
      if userID.empty?
        @participants.delete(userSessionID)
      else
        @participants.delete(userID)
      end
      @participants.delete(userID)
      @store.transaction do
        @store['spots'][spotID] = Spots[spotID] if  (!spotID.empty?)
        @store['participants'] = @participants
      end
    end
    def invalidateSession()
      session.keys.each do |k|
        session[k] = nil
      end
    end
    def getTimestamps()
      store = YAML::Store.new 'spots.yml'
      timestamps = store.transaction { store['timestamps'] }
    end
    def checkSession(id)
      timestamps = getTimestamps()
      if timestamps[id].nil?
        return true
      end
      timestamps = getTimestamps()
      timestamps[id] + 1800 < Time.now
    end
    def removeTimestamp(id)
      store = YAML::Store.new 'spots.yml'
      timestamps = store.transaction { store['timestamps'] }
      timestamps.delete(id)
      store.transaction do
        store['timestamps'] = timestamps
      end
    end
    def removeUnfinishedBookings()
      timestamps = getTimestamps()
      spots = getSpotsFromDB()
      participants = getParticipantsFromDB()
      timestamps.each do | k,v |
        if checkSession(k) 
          if (spots.values.include?(k)) 
            if participants[k].nil?
              removeUnintentionalBookings(spots.key(k))
              removeTimestamp(k)
            end
          end
        end
      end
    end
    def getDate(params)
      timestamps = getTimestamps()
      datestr = params["date"].nil? ? timestamps[params["sessionID"]].to_s : params["date"]
      if datestr.empty?
        nil
      else
        date = Date.parse datestr
        date.strftime("%d.%m.%Y")
      end
    end
    def createCSV()
      participants = getParticipantsFromDB()
      params = {}
      CSV.generate do |csv|
        csv << TableHeader
        participants.keys.each do |k|
          a = []
          a.push(participants[k]["company"])
          a.push(participants[k]["street"])
          a.push(participants[k]["zip"])
          a.push(participants[k]["city"])
          if participants[k]["gender"] == "w"
            a.push("Frau")
          elsif participants[k]["gender"] == "m"
            a.push("Herr")
          else
            a.push("-")
          end
          a.push(participants[k]["title"])
          a.push(participants[k]["fname"])
          a.push(participants[k]["lname"])
          a.push(participants[k]["department"])
          a.push(participants[k]["phone"])
          a.push(participants[k]["fax"])
          a.push(participants[k]["mail"])
          if participants[k]["ugender"] == "w"
            a.push("Frau")
          elsif participants[k]["ugender"] == "m"
            a.push("Herr")
          else
            a.push("-")
          end
          a.push(participants[k]["utitle"])
          a.push(participants[k]["ufname"])
          a.push(participants[k]["ulname"])
          a.push(participants[k]["anz"])
          a.push(participants[k]["lp"])
          if participants[k]["booking"] == "on"
            a.push("Ja")
          else
            a.push("Nein")
          end
          if participants[k]["pres"] == "on"
            a.push("Ja")
          else
            a.push("Nein")
          end
          if participants[k]["elev"] == "on"
            a.push("Ja")
          else
            a.push("Nein")
          end
          if participants[k]["inv"] == "on"
            a.push("Ja")
          else
            a.push("Nein")
          end
          a.push(participants[k]["spotID"])
          params["date"] = participants[k]["date"]
          params["sessionID"] = participants[k]["sessionID"]
          a.push(getDate(params))
          targetGroup = []
          if participants[k]["Informatik"] == "on"
            targetGroup.push("Informatik")
          end
          if participants[k]["Medieninformatik"] == "on"
            targetGroup.push("Medieninformatik")
          end
          if participants[k]["Medizininformatik"] == "on"
            targetGroup.push("Medizininformatik")
          end
          if participants[k]["Augenoptik"] == "on"
            targetGroup.push("Augenoptik/Optische Gerätetechnik")
          end
          if participants[k]["Ingenieurwissenschaften"] == "on"
            targetGroup.push("Ingenieurwissenschaften")
          end
          if participants[k]["Maschinenbau"] == "on"
            targetGroup.push("Maschinenbau")
          end
          if participants[k]["Wirtschaftsingenieurwesen"] == "on"
            targetGroup.push("Wirtschaftsingenieurwesen")
          end
          if participants[k]["Betriebswirtschaftslehre"] == "on"
            targetGroup.push("Betriebswirtschaftslehre")
          end
          if participants[k]["Wirtschaftsinformatik"] == "on"
            targetGroup.push("Wirtschaftsinformatik")
          end
          a.push("#{targetGroup.join(", ")}")
          a.push(participants[k]["agb"])
          csv << a
        end
      end
    end
  end

  get '/' do
    createDB()
    @store = YAML::Store.new 'spots.yml'
    @participants = @store.transaction { @store['participants'] }
    if @participants.keys.count <= 32
      erb :reg_step_1
    else
      erb :stop    
    end
  end

  post '/validate_step_one' do
    if params["lp"] == "basic" || params["lp"] == "comfort" || params["lp"] == "comfortp"
      session[:lp] = params["lp"]
      if session[:sessionID].nil?
        sessionID = SecureRandom.hex
        session[:sessionID] = sessionID
        setTimeStamp(sessionID)
      end
      redirect "/step_two"
    else
      flash[:error] = "Bitte wählen Sie ein Leistungspaket."
      redirect "/"
    end
  end

  get '/step_two' do
    erb :reg_step_2
  end

  get '/invalid_session' do
    invalidateSession()
    erb :invalidSession
  end

  post '/validate_step_two' do
    session[:booking] = params["booking"]
    session[:pres] = params["pres"]
    session[:elev] = params["elev"]
    session[:inv] = params["inv"]
    session[:bookingincl] = params["bookingincl"]
    if checkSession(session[:sessionID])
      redirect "invalid_session"
    elsif params["booking"] == "on" || params["bookingincl"] == "on" 
      redirect "step_three"
    else
      redirect "step_four"
    end
  end

  get '/step_three' do
    removeUnfinishedBookings()
    getSpotsFromDB()
    erb :reg_step_3
  end

  post '/validate_step_three' do
    if checkSession(session[:sessionID])
      redirect "invalid_session"
    else
      removeMultiBookings(session[:sessionID])
      getSpotsFromDB()
      erb :reg_step_3
    end
  end

  get '/validate_step_three' do
    removeUnfinishedBookings()
    if checkSession(session[:sessionID])
      redirect "invalid_session"
    else
      getSpotsFromDB()
      params['spotID'] = session[:spotID]
      erb :reg_step_3
    end
  end

  post '/step_four' do
    if checkSession(session[:sessionID])
      redirect "invalid_session"
    else
      session[:spotID] = params['spotID']
      bookSpot(session[:spotID], session[:sessionID])
      redirect "step_four"
    end
  end

  get '/step_four' do
    erb :reg_step_4
  end

  post '/validate_step_four' do
    if checkSession(session[:sessionID])
      redirect "invalid_session"
    else
      session[:company] = params['company']
      session[:street] = params['street']
      session[:zip] = params['zip']
      session[:city] = params['city']
      session[:gender] = params['gender']
      session[:title] = params['title']
      session[:fname] = params['fname']
      session[:lname] = params['lname']
      session[:department] = params['department']
      session[:phone] = params['phone']
      session[:fax] = params['fax']
      session[:mail] = params['mail']
      session[:ugender] = params['ugender']
      session[:utitle] = params['utitle']
      session[:ufname] = params['ufname']
      session[:ulname] = params['ulname']
      session[:anz] = params['anz']
      session[:Informatik] = params['Informatik']
      session[:Medieninformatik] = params['Medieninformatik']
      session[:Medizininformatik] = params['Medizininformatik']
      session[:Augenoptik] = params['Augenoptik']
      session[:Ingenieurwissenschaften] = params['Ingenieurwissenschaften']
      session[:Maschinenbau] = params['Maschinenbau']
      session[:Wirtschaftsingenieurwesen] = params['Wirtschaftsingenieurwesen']
      session[:Betriebswirtschaftslehre] = params['Betriebswirtschaftslehre']
      session[:Wirtschaftsinformatik] = params['Wirtschaftsinformatik']
      redirect "evaluate"
    end
  end

  get '/evaluate' do
    if checkSession(session[:sessionID])
      redirect "invalid_session"
    else
      targetGroup = []
      if session[:Informatik] == "on"
        targetGroup.push("Informatik")
      end
      if session[:Medieninformatik] == "on"
        targetGroup.push("Medieninformatik")
      end
      if session[:Medizininformatik] == "on"
        targetGroup.push("Medizininformatik")
      end
      if session[:Augenoptik] == "on"
        targetGroup.push("Augenoptik/Optische Gerätetechnik")
      end
      if session[:Ingenieurwissenschaften] == "on"
        targetGroup.push("Ingenieurwissenschaften")
      end
      if session[:Maschinenbau] == "on"
        targetGroup.push("Maschinenbau")
      end
      if session[:Wirtschaftsingenieurwesen] == "on"
        targetGroup.push("Wirtschaftsingenieurwesen")
      end
      if session[:Betriebswirtschaftslehre] == "on"
        targetGroup.push("Betriebswirtschaftslehre")
      end
      if session[:Wirtschaftsinformatik] == "on"
        targetGroup.push("Wirtschaftsinformatik")
      end
      @TargetGroup = ("#{targetGroup.join(", ")}")
      erb :val
    end
  end

  post '/success' do
    session[:agb] = params['agb-box']
    data = session.to_h
    saveParticipant(data)
    @mail = session[:mail]
    writeMail(["#{@mail}","#{ENV['MAIL1']}"], data)
    invalidateSession()
    erb :success
  end

  get '/login' do
    if session[:passwordhash] == ENV['PASSWORDHASH']
      redirect "backend"
    else
      erb :login
    end
  end

  post '/backend' do
    if params["inputEmail"] == ENV['BUSERNAME'] && params["inputPassword"] == ENV['PASSWORD']
      session[:passwordhash] = ENV['PASSWORDHASH']
      redirect "backend"
    elsif session[:passwordhash] == ENV['PASSWORDHASH']
      if (!params["deleteUser"].nil?)
        deletebooking(params["spotID"], params["userID"], params["userSessionID"])
        redirect "backend"
      elsif (params["detail"] == "on") 
        @params = params.to_h
        targetGroup = []
        if @params["Informatik"] == "on"
          targetGroup.push("Informatik")
        end
        if @params["Medieninformatik"] == "on"
          targetGroup.push("Medieninformatik")
        end
        if @params["Medizininformatik"] == "on"
          targetGroup.push("Medizininformatik")
        end
        if @params["Augenoptik"] == "on"
          targetGroup.push("Augenoptik/Optische Gerätetechnik")
        end
        if @params["Ingenieurwissenschaften"] == "on"
          targetGroup.push("Ingenieurwissenschaften")
        end
        if @params["Maschinenbau"] == "on"
          targetGroup.push("Maschinenbau")
        end
        if @params["Wirtschaftsingenieurwesen"] == "on"
          targetGroup.push("Wirtschaftsingenieurwesen")
        end
        if @params["Betriebswirtschaftslehre"] == "on"
          targetGroup.push("Betriebswirtschaftslehre")
        end
        if @params["Wirtschaftsinformatik"] == "on"
          targetGroup.push("Wirtschaftsinformatik")
        end
        @TargetGroup = ("#{targetGroup.join(", ")}")
        @date = getDate(@params)
        @spots = getSpotsFromDB()
        params["detail"] = nil
        erb :detail
      elsif (params["resend"] == "on")
        params["mail"] = params["new-mail"]
        params.delete("resend")
        params.delete("detail")
        params.delete("details")
        params.delete("new-mail")
        @params = params.to_h
        saveParticipant(@params)
        writeMail(["#{@params["mail"]}","#{ENV['MAIL1']}"], @params)
        flash[:success] = "Bestätigungs-E-Mail erfolgreich erneut gesendet."
        redirect "backend"
      elsif (params["rebook"] == "on")
        params.delete("resend")
        params.delete("detail")
        params.delete("details")
        params.delete("new-mail")
        params.delete("rebook")
        @params = params.to_h
        if !(params["nSpotID"] == params["spotID"]) && !(params["nSpotID"] == "-")
          puts "true"
          @params["spotID"] = params["nSpotID"]
          @params.delete("nSpotID")
          removeMultiBookings(@params["sessionID"])
          bookSpot(@params["spotID"], @params["sessionID"])
          @params["booking"] = 'on'
          if Spots[@params["spotID"]] == "c" && !(@params["lp"] == "comfortp")
            @params["lp"] = 'comfort'
          end
        end
        saveParticipant(@params)
        @spots = getSpotsFromDB()
        params["detail"] = nil
        @msg = "Buchungsdetails erfolgreich geändert."
        erb :detail
      end
    end
  end
  get '/backend' do
    if session[:passwordhash] == ENV['PASSWORDHASH']
      @store = YAML::Store.new 'spots.yml'
      getParticipantsFromDB()
      getSpotsFromDB()
      @user = Hash.new()
      @user["users"] = {}
      @participants.keys.each do |k|
        spot = @spots.select {|ks,vs| vs == k}
        @user["users"][@participants[k]] = spot.keys[0]
      end
      erb :backend
    else
      flash[:error] = "E-Mail-Adresse oder Password Falsch."
      redirect "/login"
    end
  end
  get '/csv' do
    if session[:passwordhash] == ENV['PASSWORDHASH']
      content_type 'application/csv'
      attachment   "fkm-#{Time.now.strftime("%d-%m-%Y-%H-%M")}.csv"
      createCSV()
    end
  end
  get '/download/:path/:file' do |path, file|
    file = File.join('./uploads/', path, file)
    puts file.inspect
    send_file(file, :disposition => 'attachment', :filename => File.basename(file))
  end
end
