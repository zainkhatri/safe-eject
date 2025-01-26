#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Create the sleep script
cat > /usr/local/bin/sleep-eject.sh << 'EOL'
#!/bin/bash

LOG_FILE="/tmp/ssd-eject.log"
VOLUME_NAME="ZAIN"

log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
}

get_disk_id() {
    local volume="$1"
    diskutil info "/Volumes/$volume" 2>/dev/null | grep "Device Node:" | awk '{print $NF}'
}

wait_for_unmount() {
    local volume="$1"
    local max_wait=10
    local count=0
    
    while [ $count -lt $max_wait ] && [ -d "/Volumes/$volume" ]; do
        sleep 1
        count=$((count + 1))
        log_message "Waiting for unmount... ($count/$max_wait)"
    done
    
    [ ! -d "/Volumes/$volume" ]
}

eject_drive() {
    if [ ! -d "/Volumes/$VOLUME_NAME" ]; then
        log_message "$VOLUME_NAME is not mounted"
        return 0
    fi

    log_message "Starting ejection process for $VOLUME_NAME"
    
    # Get the disk identifier
    local disk_id=$(get_disk_id "$VOLUME_NAME")
    if [ -z "$disk_id" ]; then
        log_message "Could not find disk identifier for $VOLUME_NAME"
        return 1
    fi
    log_message "Found disk ID: $disk_id"
    
    # Sync to ensure all writes are complete
    sync
    sleep 1
    
    # Method 1: Try diskutil with disk ID
    log_message "Attempting diskutil eject with disk ID..."
    diskutil eject "$disk_id" >> "$LOG_FILE" 2>&1
    sleep 2
    
    if wait_for_unmount "$VOLUME_NAME"; then
        log_message "Successfully ejected with diskutil (disk ID)"
        sleep 1  # Give system time to complete
        return 0
    fi
    
    # Method 2: Try Finder
    log_message "Disk ID eject failed, trying Finder..."
    osascript -e "tell application \"Finder\" to eject \"$VOLUME_NAME\"" >> "$LOG_FILE" 2>&1
    sleep 2
    
    if wait_for_unmount "$VOLUME_NAME"; then
        log_message "Successfully ejected with Finder"
        sleep 1  # Give system time to complete
        return 0
    fi
    
    # Method 3: Force unmount as last resort
    log_message "Normal eject failed, attempting force unmount..."
    diskutil unmountDisk force "$disk_id" >> "$LOG_FILE" 2>&1
    sleep 2
    
    if wait_for_unmount "$VOLUME_NAME"; then
        log_message "Successfully force unmounted"
        sleep 1  # Give system time to complete
        return 0
    fi
    
    log_message "All eject methods failed"
    return 1
}

# Give system time to settle before starting
sleep 1

log_message "Sleep/lid-close detected - beginning ejection sequence"
eject_drive

# Wait a bit before allowing sleep
sleep 2
EOL

# Make the script executable
chmod +x /usr/local/bin/sleep-eject.sh

# Create user's sleep script
USER_HOME="/Users/$(logname)"
cat > "$USER_HOME/.sleep" << 'EOL'
#!/bin/bash
/usr/local/bin/sleep-eject.sh
EOL

# Set proper permissions
chmod +x "$USER_HOME/.sleep"
chown $(logname):staff "$USER_HOME/.sleep"

# Stop any existing sleepwatcher service
su - $(logname) -c "brew services stop sleepwatcher" 2>/dev/null

# Start sleepwatcher service as user
su - $(logname) -c "brew services start sleepwatcher"

echo "Setup complete! Your SSD will now automatically eject when:"
echo "- The system goes to sleep"
echo "- The laptop lid is closed"
echo ""
echo "To monitor the logs in real-time, use:"
echo "sudo tail -f /tmp/ssd-eject.log"
echo ""
echo "To verify sleepwatcher is running:"
echo "brew services list | grep sleepwatcher"
echo ""
echo "Testing configuration..."
/usr/local/bin/sleep-eject.sh
