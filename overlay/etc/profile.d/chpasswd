[ ! -f "/etc/shadow-" ] && {
	echo "It's your first login. You are required to change your password:"
	trap 'echo; echo "You will be reminded again the next time you login."; stty echo; trap - INT; return' INT
	while true; do
		echo -n "Password: "; stty -echo; read p1; echo; echo -n "Confirm: "; read p2; stty echo; echo
		[ -z "$p1" ] && echo "Password cannot be empty. Retry." && continue
		[ "$p1" = "$p2" ] && { echo "root:$p1" | chpasswd -c sha512 && { echo "Password updated."; break; } || echo "Update failed. Retry."; } || echo "Password mismatch. Retry."
	done
}
trap - INT
