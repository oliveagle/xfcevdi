#!/usr/bin/env bash
### every exit != 0 fails the script
set -e

# Set password for user
PASS=${PASS:-$(pwgen -s 12 1)}

## Change SSH settings
# Enable password auth and host keys
sed -i "s/#PasswordAuthentication/PasswordAuthentication/g" /etc/ssh/sshd_config
sed -i 's/#HostKey/HostKey/g' /etc/ssh/sshd_config
# Be sure root login is always disabled (for security reasons)!
sed -i "s/#PermitRootLogin.*/PermitRootLogin no/g" /etc/ssh/sshd_config

## Create D-bus daemon runtime directory
mkdir -p /run/dbus

## Change rsyslog settings
# Disable kernel logging
sed -i "s/module(load=\"imklog\")/#module(load=\"imklog\")/g" /etc/rsyslog.conf

## PulseAudio?
# Should I create a /run/pulse maybe?
# Should I create a /run/user/1000 (is that normal under Debian?)
# Should I set XDG_RUNTIME_DIR env var to /run/user/1000

## Additional Firefox settings
{
  echo '# Enable xrender in Firefox ESR (very useful for X2Go performance)'
  echo 'pref("gfx.xrender.enabled", true);'
  echo '# Enable Google by default as homepage'
  echo 'pref("browser.startup.homepage", "https://google.com");'
  echo 'pref("browser.startup.firstrunSkipsHomepage", false);'
  echo '# Do not show "what is new"'
  echo 'pref("browser.startup.homepage_override.mstone", "ignore");'
  echo '# Empty welcome URL'
  echo 'pref("startup.homepage_welcome_url", "");'
  echo '# Disable first run infobar'
  echo 'pref("toolkit.telemetry.reportingpolicy.firstRun", false);'
  echo "# No reports will be sent (won't ask for privacy policy anymore)"
  echo 'pref("datareporting.policy.dataSubmissionEnabled", false);'
  echo '# Empty firstRun URL'
  echo 'pref("datareporting.policy.firstRunURL", "");'
} >>/etc/firefox-esr/firefox-esr.js

# Add new user
useradd -ms /bin/bash -u "$USER_ID" -G "$GROUP_LIST" "$USERNAME"
echo "$USERNAME:$PASS" | chpasswd

## MetaTrader 5 (Linux/Wine) - install or refresh on first container start.
# Controlled by MT5_INSTALL (yes/no). The installer runs as the new user so
# its Wine prefix lives in the user's persistent home.
if [ "${MT5_INSTALL:-yes}" = "yes" ]; then
  echo "Info: installing MetaTrader 5 for user '${USERNAME}'..."
  if ! su -l "$USERNAME" -c "/usr/local/bin/mt5-install"; then
    echo "Warn: MetaTrader 5 install failed (CDN may be unreachable)." >&2
    echo "      The terminal can be installed later:  mt5-install" >&2
  fi
fi

# Schedule the periodic upgrade as the real user (overwrites the placeholder
# cron baked into the image, which is inert until setup.sh replaces it).
if [ "${MT5_AUTOUPDATE:-yes}" = "yes" ]; then
  cat >/etc/cron.d/mt5-autoupdate <<CRON
# /etc/cron.d/mt5-autoupdate (written by setup.sh on first container start)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 */6 * * * ${USERNAME} flock -n /tmp/mt5-autoupdate.lock /usr/local/bin/mt5-autoupdate >>/var/log/mt5-autoupdate.log 2>&1
CRON
  chmod 0644 /etc/cron.d/mt5-autoupdate
fi

# Allow user to execute apt commands (install new software)
if [ "$ALLOW_APT" = "yes" ]; then
  # We allow only apt commands
  if [ "$ENTER_PASS" = "no" ]; then
    # Allow sudo command without entering a password to the new user
    echo "${USERNAME} ALL=(root) NOPASSWD:/usr/bin/apt update, /usr/bin/apt install *, /usr/bin/apt upgrade, /usr/bin/apt-get update, /usr/bin/apt-get install *, /usr/bin/apt-get upgrade" >>/etc/sudoers
  else
    echo "${USERNAME} ALL=(root) /usr/bin/apt update, /usr/bin/apt install *, /usr/bin/apt upgrade, /usr/bin/apt-get update, /usr/bin/apt-get install *, /usr/bin/apt-get upgrade" >>/etc/sudoers
  fi
fi

# Show the password only once in the terminal
echo ""
echo "Warn: The username and password will be printed only once!"
echo -e "Info: Default username is '${USERNAME}' with the password: ${PASS}\n\n"

# Unset password!
unset PASS

touch /app/.setup_done

# Self-destruct
rm -- "$0"
