# frozen_string_literal: true

class FilterTokensInFacteurMailings < ActiveRecord::Migration[7.1]
  def up
    execute <<~'SQL'
      UPDATE facteur_mailings
      SET body = regexp_replace(
        body,
        '(\A|[^A-Za-z0-9_])(reset_password_token|confirmation_token|unlock_token|invitation_token)=[^&"''<># \t\r\n\f\v]+',
        '\1\2=[FILTERED]',
        'g'
      )
      WHERE body ~ '(\A|[^A-Za-z0-9_])(reset_password_token|confirmation_token|unlock_token|invitation_token)=[^&"''<># \t\r\n\f\v]+'
    SQL

    execute <<~'SQL'
      UPDATE facteur_mailings
      SET mailer_params = jsonb_set(mailer_params, '{0}', '"[FILTERED]"')
      WHERE mailer_method IN (
        'reset_password_instructions', 'confirmation_instructions', 'unlock_instructions', 'invitation_instructions'
      )
        AND jsonb_typeof(mailer_params) = 'array'
        AND jsonb_typeof(mailer_params -> 0) = 'string'
        AND mailer_params ->> 0 <> '[FILTERED]'
        AND (sent_at IS NOT NULL OR skipped_at IS NOT NULL OR error_at IS NOT NULL)
    SQL
  end

  def down
    # The filtered tokens cannot be restored
  end
end
