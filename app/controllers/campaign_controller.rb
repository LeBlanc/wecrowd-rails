class CampaignController < ApplicationController
  
  before_filter :get_campaign, except: [ :new, :create ]
  before_filter :check_user,   except: [ :new, :create, :index, :donate, :make_donation, :donation_success ]
  
  # GET /campaign/12345
  # the public page for the campaign
  def index
  end

  # GET /campaign/new
  # allows merchants to register and create a new campaign
  def new
    @campaign = Campaign.new
  end
  
  # POST /campaign/new
  # handles the form on the campaign creation page
  def create
    # if the user is signed in, just use that user
    if signed_in?
      @user = current_user
    else # otherwise register a user from the information provided
      @user = User.new({:name => params[:user_name], :email => params[:user_email]})
      @user.password = params[:user_password]
      if @user.valid? && @user.save
        sign_in(@user)
      else
        error(@user.errors.full_messages)
        return redirect_to("/campaign/new")
      end
    end
    # create the campaign from the details provided
    @campaign = Campaign.new({
      user_id: @user.id,
      name: params[:campaign_name],
      description: params[:campaign_description],
      goal: params[:campaign_goal],
      account_type: params[:account_type]
    })
    if @campaign.valid? && @campaign.save
      # if the campaign is valid, register the user on WePay and create a WePay account for it
      @user.register_on_wepay(request.ip, request.env['HTTP_USER_AGENT'])
      @user.create_wepay_account
      message("Your campaign has been created successfully!")
      redirect_to("/campaign/details/#{@campaign.id}")
    else
      error(@campaign.errors.full_messages)
      return redirect_to("/campaign/new")
    end
  end

  # GET /campaign/details/12345
  # the private details page for the campaign that lets the merchant view and edit the campaign details
  def details
    @payments = @campaign.payments
  end

  # POST /campaign/edit/12345
  # handles the form post from the details page, edits the campaign
  def edit
    if @campaign.update_attributes({
      name: params[:campaign_name],
      description: params[:campaign_description],
      goal: params[:campaign_goal],
      account_type: params[:account_type]
    })
      message("Your campaign has been edited successfully!")
    else
      error(@campaign.errors.full_messages)
    end
    redirect_to("/campaign/details/#{@campaign.id}")
  end

  # GET /campaign/donate/12345
  # the donation page, asks for donation amount and credit card details
  def donate
    # prefill the credit card form with data so demo users don't have to enter it in every time
    params[:user_name] ||= "Test User"
    params[:user_email] ||= "test@example.com"
    params[:cc_number] ||= "5496198584584769"
    params[:cvv] ||= "123"
    params[:expiration_month] ||= "11"
    params[:expiration_year] ||= "2015"
    params[:zip] ||= "94025"
  end
  
  # POST /campaign/donate/12345
  # handles the form POST from the donation page
  # credit card info is not sent to the server,
  # we only receive the credit_card_id which we can use to create a checkout
  def make_donation
    # try to see if the donor is already in the database
    @user = User.find_by_email(params[:user_email])
    if !@user # if not, then create the user
      @user = User.new({
        name: params[:user_name],
        email: params[:user_email]
      })
      unless @user.valid? && @user.save
        error(@user.errors.full_messages)
        return redirect_to("/campaign/donate/#{@campaign.id}")
      end
    end
    
    # create the payment object with the details provided
    @payment = Payment.new({
      campaign_id: @campaign.id,
      payer_id: @user.id,
      wepay_credit_card_id: params[:credit_card_id],
      amount: params[:amount],
    })
    if !@payment.valid?
      error(@payment.errors.full_messages)
      return redirect_to("/campaign/donate/#{@campaign.id}")
    end
    # if the payment is valid, make the /checkout/create call
    # and then save the updated details
    if @payment.valid? && @payment.create_checkout && @payment.save
      message("Donation Made!")
      redirect_to("/campaign/#{@campaign.id}/")
    else
      error(@payment.errors.full_messages)
      redirect_to("/campaign/donate/#{@campaign.id}")
    end
  end

  def donation_success
  end
  
  private
  
  # find the campaign from the campaign_id provided in the route (see routes.rb)
  def get_campaign
    @campaign = Campaign.find(params[:campaign_id])
  end
  
  # for private pages, make sure the user who is logged in is the owner of the campaign
  def check_user
    @user = authenticate(@campaign.user_id, request.path, nil)
  end
end