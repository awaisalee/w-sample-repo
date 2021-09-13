class Api::ApiController < ApplicationController
  include Secured
  skip_before_action :verify_authenticity_token
  before_action :build_params

  private

  def build_params
    if params[:data] && params[:data][:attributes]
      type = params[:data][:type].underscore.singularize
      params[type] = params[:data][:attributes].transform_keys(&:underscore)
    end
  end
end
