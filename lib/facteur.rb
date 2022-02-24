# frozen_string_literal: true

require 'facteur/engine'
require 'facteur/models/concerns/devise_facteurable'
require 'facteur/models/concerns/application_recordable'
require 'facteur/models/mailing'
require 'facteur/workers/mailing_delivery_worker'
require 'facteur/workers/mail_provider_hook_worker'
