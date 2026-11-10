# frozen_string_literal: true

require 'rails/generators'
require 'generators/facteur/active_record_generator'

RSpec.describe Facteur::Generators::ActiveRecordGenerator do
  around do |example|
    Dir.mktmpdir do |dir|
      @destination = dir
      example.run
    end
  end

  def run_generator
    described_class.start(['--quiet'], destination_root: @destination)
  end

  def migrations
    Dir[File.join(@destination, 'db', 'migrate', '*.rb')].map { |path| File.basename(path) }.sort
  end

  def migration_path(name)
    Dir[File.join(@destination, 'db', 'migrate', "*_#{name}.rb")].first
  end

  it 'copies every migration on a fresh install, in order' do
    run_generator

    expect(migrations.size).to eq(3)
    expect(migrations[0]).to match(/\A\d{14}_create_facteur_mailings\.rb\z/)
    expect(migrations[1]).to match(/\A\d{14}_add_tracking_to_facteur_mailings\.rb\z/)
    expect(migrations[2]).to match(/\A\d{14}_filter_tokens_in_facteur_mailings\.rb\z/)
  end

  it 'does not duplicate migrations when run twice' do
    run_generator
    first_run = migrations

    run_generator

    expect(migrations).to eq(first_run)
  end

  it 'only copies the missing migrations when the previous ones already exist' do
    FileUtils.mkdir_p(File.join(@destination, 'db', 'migrate'))
    File.write(File.join(@destination, 'db', 'migrate', '20220101000000_create_facteur_mailings.rb'), '')
    File.write(File.join(@destination, 'db', 'migrate', '20261109033137_add_tracking_to_facteur_mailings.rb'), '')

    run_generator

    expect(migrations.size).to eq(3)
    expect(migrations.first(2))
      .to eq(%w[20220101000000_create_facteur_mailings.rb 20261109033137_add_tracking_to_facteur_mailings.rb])
    expect(migrations.last).to match(/\A\d{14}_filter_tokens_in_facteur_mailings\.rb\z/)
  end

  it 'generates a reversible tracking migration' do
    run_generator
    load migration_path('add_tracking_to_facteur_mailings')
    connection = ActiveRecord::Base.connection
    columns = -> { connection.columns(:facteur_mailings).map(&:name) }

    ActiveRecord::Migration.suppress_messages { AddTrackingToFacteurMailings.new.migrate(:down) }
    expect(columns.call).not_to include('skipped_at', 'skip_reason', 'provider_message_ids')

    ActiveRecord::Migration.suppress_messages { AddTrackingToFacteurMailings.new.migrate(:up) }
    expect(columns.call).to include('skipped_at', 'skip_reason', 'provider_message_ids')
    expect(connection.columns(:facteur_mailings).find { |c| c.name == 'provider_message_ids' })
      .to have_attributes(sql_type: 'jsonb', null: false, default: '[]')
  ensure
    Facteur::Mailing.reset_column_information
  end

  describe 'filter_tokens_in_facteur_mailings' do
    let(:html_body) do
      '<a href="http://localhost/users/password/edit?reset_password_token=raw1&amp;locale=fr">Reset</a>'
    end
    let(:text_body) { "Confirm: http://localhost/users/confirmation?confirmation_token=raw2\nBye" }

    def create_mailing(mailer_method: 'reset_password_instructions', mailer_params: ['raw-token', {}], **attributes)
      Facteur::Mailing.create!(mailer_klass: 'Devise::Mailer', mailer_method: mailer_method,
                               mailer_params: mailer_params, **attributes)
    end

    def migrate_up
      run_generator
      load migration_path('filter_tokens_in_facteur_mailings')
      ActiveRecord::Migration.suppress_messages { FilterTokensInFacteurMailings.new.migrate(:up) }
    end

    it 'filters the tokens of the stored bodies like FilterTokensService' do
      bodies = [
        html_body, text_body, "unlock_token=raw3\t/x?invitation_token=raw4&id=1#top 'x?reset_password_token=raw5'",
        '/x?my_reset_password_token=kept&token=kept', 'Hello'
      ]
      mailings = bodies.map { |body| create_mailing(mailer_method: 'account_creation_user_email', body: body) }

      migrate_up

      expected = bodies.map { |body| Facteur::Mailing::FilterTokensService.new(Facteur::Mailing.new(body: body)).call.body }
      expect(mailings.map { |mailing| mailing.reload.body }).to eq(expected)
      expect(expected.first).to include('reset_password_token=[FILTERED]&amp;locale=fr')
    end

    it 'filters the token of the mailer_params of finished Devise mailings only' do
      sent = create_mailing(sent_at: Time.current, body: html_body)
      skipped = create_mailing(mailer_method: 'confirmation_instructions', skipped_at: Time.current)
      failed = create_mailing(mailer_method: 'unlock_instructions', error_at: Time.current)
      pending = create_mailing(mailer_method: 'invitation_instructions', body: html_body)
      other = create_mailing(mailer_method: 'welcome', mailer_params: ['jane@facteur.test'], sent_at: Time.current)
      hash_params = create_mailing(mailer_params: { 'token' => 'raw-token' }, sent_at: Time.current)

      migrate_up

      expect([sent, skipped, failed].map { |mailing| mailing.reload.mailer_params }).to all(eq(['[FILTERED]', {}]))
      expect(pending.reload.mailer_params).to eq(['raw-token', {}])
      expect(pending.body).not_to include('raw1')
      expect(other.reload.mailer_params).to eq(['jane@facteur.test'])
      expect(hash_params.reload.mailer_params).to eq({ 'token' => 'raw-token' })
    end

    it 'can be rolled back, without restoring anything' do
      mailing = create_mailing(sent_at: Time.current, body: html_body)
      migrate_up

      ActiveRecord::Migration.suppress_messages { FilterTokensInFacteurMailings.new.migrate(:down) }

      expect(mailing.reload.mailer_params).to eq(['[FILTERED]', {}])
    end
  end
end
