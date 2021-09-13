class WaitingListsController < ApplicationController
  def create
    resource = WaitingList.create(wait_list_params)
    respond_to do |format|
      format.js
    end
  end

  def wait_list_params
    params.permit(:email)
  end
end
