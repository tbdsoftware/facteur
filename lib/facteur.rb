# frozen_string_literal: true

require 'oj'
require 'sidekiq'
require 'facteur/engine'
require 'facteur/models/concerns/devise_facteurable'
require 'facteur/models/concerns/application_recordable'
require 'facteur/models/mailing'
require 'facteur/jobs/mailing_delivery_job'
require 'facteur/jobs/mail_provider_hook_job'
