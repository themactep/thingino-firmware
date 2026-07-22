#!/bin/sh
# floodlightd motion hook - invoked as: motion.sh "<left> <middle> <right>"
# Wire this into thingino's motion pipeline (e.g. publish MQTT, kick a snapshot,
# notify motord). Keep it fast and non-blocking; floodlightd fire-and-forgets it.

ZONES="$1" # e.g. "1 0 1"

logger -t floodlightd "motion zones: ${ZONES}"

# Example: publish to MQTT if configured (uncomment/adapt)
# . /etc/mqtt.conf 2>/dev/null && \
#   mosquitto_pub -h "$MQTT_HOST" -t "$MQTT_TOPIC/motion" -m "${ZONES}"

# Example: trigger thingino motion event
# [ -x /usr/bin/motord ] && echo "PIR ${ZONES}" > /run/motord.fifo 2>/dev/null

exit 0
