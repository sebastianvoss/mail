FROM debian:jessie

MAINTAINER Sebastian Voss

RUN apt-get update && apt-get install -y \
      exim4-daemon-heavy \
      spf-tools-perl \
      dovecot-core \
      dovecot-imapd \
      dovecot-lmtpd \
      spamassassin \
      supervisor \
    && rm -rf /var/lib/apt/lists/*

# Exim configuration files
COPY exim4/ /etc/exim4/ 
COPY checkzip /usr/local/bin/

# modify /etc/exim4/update-exim4.conf.conf
RUN sed -i -r \
      -e "/dc_eximconfig_configtype=/ s/=.*/='internet'/" \
      -e "/dc_other_hostnames=/       s/=.*/=''/" \
      -e "/dc_local_interfaces=/      s/=.*/=''/" \
      -e "/dc_use_split_config=/      s/=.*/='true'/" /etc/exim4/update-exim4.conf.conf

RUN sed -i -r \
    -e 's/# (spamd_address) =.*/\1 = 127.0.0.1 783/' \
    -e "s|# (av_scanner) =.*|\1 = cmdline:/usr/local/bin/checkzip --extensions "js,bat,btm,cmd,com,cpl,dll,exe,lnk,msi,pif,prf,reg,scr,vbs,url" --directory %s:Found banned file extensions:'(.+)'|" \
    -e 's/# (rfc1413_query_timeout) =.*/\1 = 0s/' /etc/exim4/conf.d/main/02_exim4-config_options && \
  echo "acl_smtp_dkim = acl_check_dkim" >> /etc/exim4/conf.d/main/02_exim4-config_options && \
  update-exim4.conf


# Dovecot configuration

COPY dovecot/ /etc/dovecot/

RUN sed -i -r \
      -e '/auth_mechanisms =/ s/= .*/= plain login/' \
      -e '/#!include auth-passwdfile.conf.ext/ s/#//' /etc/dovecot/conf.d/10-auth.conf && \
    sed -i \
      -e '/service auth {/ a unix_listener auth-client {\n mode = 0660 \n group = Debian-exim \n}' \
      -e '/unix_listener lmtp {/ a mode = 0660 \n group = Debian-exim' /etc/dovecot/conf.d/10-master.conf && \
    sed -i \
      -e '\|mail_location =| s|= .*|= maildir:/vmail/mail/%d/%n|' /etc/dovecot/conf.d/10-mail.conf && \
    sed -i -r \
      -e 's|#(log_path) =.*|\1 = /var/log/dovecot.log|' /etc/dovecot/conf.d/10-logging.conf && \
    sed -i -r \
      -e '/ssl =/ s/= .*/= required/' \
      -e 's|#(ssl_cert) =.*|\1 = </vmail/certs/fullchain.pem|' \
      -e 's|#(ssl_key) =.*|\1 = </vmail/certs/privkey.pem|' /etc/dovecot/conf.d/10-ssl.conf


# Spamassassin

RUN sed -i -r 's/(loadplugin Mail::SpamAssassin::Plugin::DKIM)/#\1/' /etc/spamassassin/v312.pre


# vmail config

RUN useradd -u 3000 vmail

COPY start_exim /etc/exim4/
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# expose SMTP (25), SMTP Submission (587), SMTPS (465), IMAPS (993)
EXPOSE 25 587 465 993

CMD ["/usr/bin/supervisord"]
