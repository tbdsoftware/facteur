# frozen_string_literal: true

RSpec.describe 'Webhook routes' do
  around do |example|
    webhooks = Facteur.webhooks
    example.run
  ensure
    Facteur.webhooks = webhooks
    Rails.application.reload_routes!
  end

  before { Facteur.scaleway_webhook_token = 'scaleway-secret-token' }

  def draw_routes(provider:, webhooks:)
    Facteur.provider = provider
    Facteur.webhooks = webhooks
    Rails.application.reload_routes!
  end

  def post_sendgrid_status
    post '/facteur/sendgrid', params: '[]', headers: { 'Content-Type' => 'application/json' }
    response.status
  end

  def post_scaleway_status
    post '/facteur/scaleway?facteur_token=scaleway-secret-token', params: 'not json',
                                                                  headers: { 'Content-Type' => 'text/plain' }
    response.status
  end

  it 'only draws the SendGrid webhook by default' do
    draw_routes(provider: :sendgrid, webhooks: nil)

    expect(post_sendgrid_status).to eq(403)
    expect(post_scaleway_status).to eq(404)
  end

  it "only draws the provider's webhook when webhooks is not set" do
    draw_routes(provider: :scaleway, webhooks: nil)

    expect(post_sendgrid_status).to eq(404)
    expect(post_scaleway_status).to eq(400)
  end

  it 'only draws the listed webhooks, whatever the provider' do
    draw_routes(provider: :sendgrid, webhooks: %i[scaleway])

    expect(post_sendgrid_status).to eq(404)
    expect(post_scaleway_status).to eq(400)
  end

  it 'accepts webhook names as strings' do
    draw_routes(provider: :scaleway, webhooks: %w[sendgrid scaleway])

    expect(post_sendgrid_status).to eq(403)
    expect(post_scaleway_status).to eq(400)
  end

  it 'draws no webhook for an empty list' do
    draw_routes(provider: :scaleway, webhooks: [])

    expect(post_sendgrid_status).to eq(404)
    expect(post_scaleway_status).to eq(404)
  end
end
