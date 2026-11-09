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

  it 'copies both migrations on a fresh install, creation first' do
    run_generator

    expect(migrations.size).to eq(2)
    expect(migrations.first).to match(/\A\d{14}_create_facteur_mailings\.rb\z/)
    expect(migrations.last).to match(/\A\d{14}_add_tracking_to_facteur_mailings\.rb\z/)
  end

  it 'does not duplicate migrations when run twice' do
    run_generator
    first_run = migrations

    run_generator

    expect(migrations).to eq(first_run)
  end

  it 'only copies the tracking migration when the creation one already exists' do
    FileUtils.mkdir_p(File.join(@destination, 'db', 'migrate'))
    File.write(File.join(@destination, 'db', 'migrate', '20220101000000_create_facteur_mailings.rb'), '')

    run_generator

    expect(migrations.size).to eq(2)
    expect(migrations.first).to eq('20220101000000_create_facteur_mailings.rb')
    expect(migrations.last).to match(/\A\d{14}_add_tracking_to_facteur_mailings\.rb\z/)
  end

  it 'generates a reversible tracking migration' do
    run_generator
    path = Dir[File.join(@destination, 'db', 'migrate', '*_add_tracking_to_facteur_mailings.rb')].first
    load path
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
end
