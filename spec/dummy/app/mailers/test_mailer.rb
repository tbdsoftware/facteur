# frozen_string_literal: true

class TestMailer < ApplicationMailer
  def welcome(to, subject = 'Welcome')
    mail(to: to, subject: subject, body: "Hello #{to}", content_type: 'text/plain')
  end

  def notification
    mail(to: params[:to], subject: params[:subject] || 'Notification', body: 'You have a notification',
         content_type: 'text/plain')
  end

  def reset_password_instructions(token, opts = {})
    link = "http://localhost/users/password/edit?reset_password_token=#{token}&amp;locale=fr"
    mail(to: opts['to'] || 'jane@facteur.test', subject: 'Reset your password',
         body: %(<p><a href="#{link}">Reset</a></p>), content_type: 'text/html')
  end
end
