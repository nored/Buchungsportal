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
require 'mail'
require 'erb'
require 'spork'

class Buchungsportal < Sinatra::Base

  helpers Sinatra::FormHelpers
  enable :sessions
  register Sinatra::Flash
  set :protection, :except => :frame_options

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

  get '/' do
    if !(File.file?("spots.yml")) 
      @store = YAML::Store.new 'spots.yml'
      @store.transaction do
        @store['spots'] ||= Spots
        @store['participants'] ||= Participants
      end
    end
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
      query = params.map{|key, value| "#{key}=#{value}"}.join("&")
      @session_id = SecureRandom.hex
      redirect "/step_two?#{query}&sessionID=#{@session_id}"
    else
      flash[:error] = "Bitte wählen Sie ein Leistungspaket."
      redirect "/"
    end
  end

  get '/step_two' do
    erb :reg_step_2
  end

  post '/validate_step_two' do
    query = params.map{|key, value| "#{key}=#{value}"}.join("&")
    if params["booking"] == "on" || params["bookingincl"] == "on" 
      redirect "step_three?#{query}"
    else
      redirect "step_four?#{query}"
    end
  end

  get '/step_three' do
    @store = YAML::Store.new 'spots.yml'
    @spots = @store.transaction { @store['spots'] }
    erb :reg_step_3
  end

  post '/validate_step_three' do
    @id = params['spotID']
    @session_id = params['sessionID']
    puts params.class
    @aboard_params = params.to_h
    @aboard_params.delete("spotID")
    @store = YAML::Store.new 'spots.yml'  
    @spots = @store.transaction { @store['spots'] }
    @oldSpots = @store.transaction { @store['spots'] }.nil? ? Spots : @store.transaction { @store['spots'] }
    if @spots.values.include?(@session_id)
      old_Spots = @spots.select {|k,v| v == @session_id}
      old_Spots.keys.each do |k| 
        @store.transaction do
          @store['spots'] ||= @oldSpots
          @store['spots'][k] = Spots[k]
        end
      end
    end
    erb :reg_step_3
  end

  post '/step_four' do
    @id = params['spotID']
    @session_id = params['sessionID']
    @store = YAML::Store.new 'spots.yml'
    @oldSpots = @store.transaction { @store['spots'] }.nil? ? Spots : @store.transaction { @store['spots'] }
    @store.transaction do
      @store['spots'] ||= @oldSpots
      @store['spots'][@id] = @session_id
    end
    erb :reg_step_4
  end

  get '/step_four' do
    erb :reg_step_4
  end

  post '/validate_step_four' do
    erb :val
  end

  post '/success' do
    @recipient = params["mail"]
    Spork.prefork do  
      @params = params.to_h
      @mails = ["#{@recipient}","#{ENV['MAIL1']}"]
      @store = YAML::Store.new 'spots.yml'
      @session_id = params['sessionID']
      @company = params["company"]
      @oldParticipants = @store.transaction { @store['participants'] }.nil? ? Participants : @store.transaction { @store['participants'] }
      @store.transaction do
        @store['participants'] ||= @oldSpots
        @store['participants'][@session_id] = @company
      end
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
      @mails.each do |m|
        Mail.deliver do
          to "#{m}"
          from "#{ENV['MAIL2']}"
          subject "Buchungsbestätigung Firmenkontaktmesse 2019"
          content_type 'text/html; charset=UTF-8'
          body "#{mail}"
        end
      end 
    end
    erb :success
  end

  get '/login' do
    erb :login
  end

  post '/backend' do
    if params["inputEmail"] == ENV['BUSERNAME'] && params["inputPassword"] == ENV['PASSWORD']
      @store = YAML::Store.new 'spots.yml'
      @participants = @store.transaction { @store['participants'] }
      @spots = @store.transaction { @store['spots'] }
      if (!params["deleteUser"].nil?)
        @spots.delete(params["spotID"])
        @participants.delete(params["userID"])
        @store.transaction do
          @store['spots'][params["spotID"]] = Spots[params["spotID"]]
          @store['participants'] = @participants
        end
      end
      @user = Hash.new()
      @user["users"] = {}
      @participants.keys.each do |k|
        spot = @spots.select {|ks,vs| vs == k}
        @user["users"][@participants[k]] = spot.keys[0]
      end
      puts @user
      erb :backend
    else
      flash[:error] = "E-Mail-Adresse oder Password Falsch."
      redirect "/login"
    end
  end
end
