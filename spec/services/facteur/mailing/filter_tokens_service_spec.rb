# frozen_string_literal: true

RSpec.describe Facteur::Mailing::FilterTokensService do
  def filter(mailing)
    described_class.new(mailing).call
  end

  def filtered_body(body)
    filter(Facteur::Mailing.new(body: body)).body
  end

  describe 'body' do
    described_class::TOKEN_PARAMS.each do |param|
      it "filters #{param} in a text body" do
        expect(filtered_body("Open http://localhost/x?#{param}=s3cr3t-T0ken_1 to continue"))
          .to eq("Open http://localhost/x?#{param}=[FILTERED] to continue")
      end
    end

    it 'filters a token in an HTML link, up to the next parameter' do
      body = '<a href="http://localhost/users/password/edit?locale=fr&amp;reset_password_token=abc123&amp;x=1">Reset</a>'

      expect(filtered_body(body))
        .to eq('<a href="http://localhost/users/password/edit?locale=fr&amp;reset_password_token=[FILTERED]&amp;x=1">Reset</a>')
    end

    {
      'a double quote' => %(href="/x?confirmation_token=abc"),
      'a single quote' => "href='/x?confirmation_token=abc'",
      'a tag' => '<p>/x?confirmation_token=abc</p>',
      'a fragment' => '/x?confirmation_token=abc#top',
      'a new line' => "/x?confirmation_token=abc\nBye",
      'a tab' => "/x?confirmation_token=abc\tBye"
    }.each do |name, body|
      it "stops the token at #{name}" do
        expect(filtered_body(body)).to eq(body.sub('abc', '[FILTERED]'))
      end
    end

    it 'filters every token of the body, at the start of it too' do
      body = "unlock_token=a1\n/x?invitation_token=b2&reset_password_token=c3"

      expect(filtered_body(body)).to eq("unlock_token=[FILTERED]\n/x?invitation_token=[FILTERED]&reset_password_token=[FILTERED]")
    end

    it 'leaves other parameters and longer parameter names alone' do
      body = '/x?token=a1&my_reset_password_token=b2&reset_password_token_id=c3&id=4'

      expect(filtered_body(body)).to eq(body)
    end

    it 'is idempotent' do
      body = filtered_body('/x?reset_password_token=abc')

      expect(filtered_body(body)).to eq('/x?reset_password_token=[FILTERED]')
    end

    it 'accepts a mailing without body' do
      expect(filtered_body(nil)).to be_nil
    end
  end

  describe 'mailer_params' do
    def build_mailing(mailer_method: 'reset_password_instructions', mailer_params: ['raw-token', { 'to' => 'jane@facteur.test' }],
                      **attributes)
      Facteur::Mailing.new(mailer_klass: 'Devise::Mailer', mailer_method: mailer_method, mailer_params: mailer_params,
                           **attributes)
    end

    described_class::DEVISE_METHODS.each do |mailer_method|
      it "filters the token of a sent #{mailer_method} mailing" do
        mailing = build_mailing(mailer_method: mailer_method, sent_at: Time.current)

        expect(filter(mailing).mailer_params).to eq(['[FILTERED]', { 'to' => 'jane@facteur.test' }])
      end
    end

    it 'filters the token of a skipped or failed mailing' do
      expect(filter(build_mailing(skipped_at: Time.current)).mailer_params.first).to eq('[FILTERED]')
      expect(filter(build_mailing(error_at: Time.current)).mailer_params.first).to eq('[FILTERED]')
    end

    it 'keeps the token of a pending mailing, which a retry still needs' do
      expect(filter(build_mailing).mailer_params).to eq(['raw-token', { 'to' => 'jane@facteur.test' }])
    end

    it 'leaves the params of other mailers alone' do
      mailing = build_mailing(mailer_method: 'welcome', mailer_params: ['jane@facteur.test'], sent_at: Time.current)

      expect(filter(mailing).mailer_params).to eq(['jane@facteur.test'])
    end

    it 'leaves params that do not start with a String alone' do
      mailing = build_mailing(mailer_params: { 'token' => 'raw-token' }, sent_at: Time.current)

      expect(filter(mailing).mailer_params).to eq({ 'token' => 'raw-token' })
    end
  end

  it 'returns the mailing without saving it' do
    mailing = Facteur::Mailing.create!(mailer_klass: 'TestMailer', mailer_method: 'reset_password_instructions',
                                       mailer_params: ['raw-token', {}], body: '/x?reset_password_token=raw-token',
                                       sent_at: Time.current)

    expect(filter(mailing)).to be(mailing)
    expect(mailing).to be_changed
    expect(mailing.reload.body).to eq('/x?reset_password_token=raw-token')
  end
end
