# Show gpu-upkeep warnings on interactive SSH logins (/etc/profile.d); details with gpu-upkeep.
case "$-" in
    *i*) if [ -n "${SSH_CONNECTION:-}" ]; then /usr/local/bin/gpu-upkeep status --warnings; fi ;;
esac
