# frozen_string_literal: true

require 'faraday'
require 'pry'

require 'concurrent-edge'
require 'concurrent'

# Presenter Pattern
class GithubUserPresenter
  UserPresenterInformation = Struct.new(:name, :location, :company, :bio)

  def initialize(body:)
    @body = body
  end

  def build
    UserPresenterInformation.new(
      name: fetch!(key: 'name'),
      location: fetch!(key: 'location'),
      bio: fetch!(key: 'bio'),
      company: fetch!(key: 'company')
    )
  end

  private

  def fetch!(key:)
    body.fetch(key, '')
  end

  attr_reader :body
end

# Client to communication with Github rest api
class GithubClient
  def initialize
    @connection = build_connection
  end

  def user_info(user:)
    connection.get(user)
  rescue StandardError => e
    puts e
  end

  private

  attr_reader :connection

  def build_connection
    @build_connection ||= Faraday.new(url: base_url) do |conn|
      conn.request :json
      conn.response :json
      conn.adapter Faraday.default_adapter
    end
  end

  def base_url
    'https://api.github.com/users/'
  end
end

# Business Logic and parallel requests with concurrent promises
class GithubUsersInformationServices
  def initialize(users:)
    @client = GithubClient.new
    @users = users
  end

  class EmptyUsersError < StandardError; end

  def perform
    empty_users_validation!

    promises = users_promises
    responses = promises.map(&:value!)

    responses.map do |response|
        if response.status == 429
            user_login = response.env.url.to_s.split('/').last 

            return create_retry_txt(login: user_login)
        end
      
      data = response.body
      GithubUserPresenter.new(body: data).build
    end
  end

  private

  attr_reader :client, :users

  def empty_users_validation!
    raise EmptyUsersError if users.empty?
  end

  def users_promises
    users.map do |user|
      Concurrent::Promise.execute { client.user_info(user:) }
    end
  end

  def create_retry_txt(login:)
    file_name = "users_#{current_date}"
    File.open(file_name, 'w') do |f|
        f.write(login:)
    end
  end

  def current_date
    Time.now.strftime('%B_%d_%Y')
  end
end

GithubUsersInformationServices.new(users: ['Andre-lsn'] * 50).perform
