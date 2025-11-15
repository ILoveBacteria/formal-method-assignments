chan slot_signal = [0] of { byte };

// Message
mtype = { TELEMETRY, COMMAND, IMAGE, ACK };
typedef Message {
    mtype type;
    byte  src; // 0: ground, 1: satellite 1, 2: satellite 2, 3: satellite 3
    byte  dest; // 0: ground, 1: satellite 1, 2: satellite 2, 3: satellite 3
    int   payload;
}

// grant channels
chan grant_ground1 = [0] of {bit}
chan grant_ground2 = [0] of {bit}
chan grant_ground3 = [0] of {bit}
chan grant_isl12 = [0] of {bit}
chan grant_isl13 = [0] of {bit}
chan grant_isl23 = [0] of {bit}

// Communication channels
chan to_ground1 = [0] of { Message }
chan to_ground2 = [0] of { Message }
chan to_ground3 = [0] of { Message }
chan isl12 = [0] of { Message }
chan isl13 = [0] of { Message }
chan isl23 = [0] of { Message }

// Timer channels
chan timer_on[3] = [0] of { bit }
chan timer_off[3] = [0] of { bit }
chan time_out[3] = [0] of { bit }


active proctype timeKeeper() {
    byte current_slot = 0;
    do
    :: true -> if
        :: current_slot < 7 -> current_slot = current_slot + 1;
        :: current_slot >= 7 -> current_slot = 0;
        fi
        slot_signal ! current_slot;
    od
}

active proctype coordinator() {
    byte slot = 0;
    do 
    :: slot_signal ? slot;
    :: slot == 0 -> grant_ground1 ! 1;
    :: slot == 1 -> grant_ground2 ! 1;
    :: slot == 2 -> grant_ground3 ! 1;
    :: slot == 4 -> grant_isl12 ! 1;
    :: slot == 5 -> grant_isl23 ! 1;
    :: slot == 6 -> grant_isl13 ! 1;
    od 
}

active proctype groundStation() {
    Message msg;
    // ack message to be sent back to satellites
    Message ack_message;
    ack_message.type = ACK;
    ack_message.src = 0;
    ack_message.dest = 0;
    ack_message.payload = 0;
    // counters for received messages from each satellite
    int count_received_messages[3];
    count_received_messages[0] = 0;
    count_received_messages[1] = 0;
    count_received_messages[2] = 0;
    byte state = 0; // 0: idle, 1: received from satellite 1, 2: received from satellite 2, 3: received from satellite 3
    atomic {
        do
        :: state == 0 -> if 
            :: to_ground1 ? msg ->
                state = 1;
            :: to_ground2 ? msg ->
                state = 2;
            :: to_ground3 ? msg ->
                state = 3;
            fi
        :: state == 1 -> if 
            :: grant_ground1 ? _ -> count_received_messages[0]++; state = 0; to_ground1 ! ack_message;
            :: true -> skip;
            fi
        :: state == 2 -> if 
            :: grant_ground2 ? _ -> count_received_messages[1]++; state = 0; to_ground2 ! ack_message;
            :: true -> skip;
            fi
        :: state == 3 -> if 
            :: grant_ground3 ? _ -> count_received_messages[2]++; state = 0; to_ground3 ! ack_message;
            :: true -> skip;
            fi
        od
    }
}

proctype timer(byte id) {
    bit status = 0; // 0: off, 1: on
    do
    :: timer_on[id] ? _ -> status = 1;
    :: timer_off[id] ? _ -> status = 0;
    :: status == 1 -> time_out[id] ! 1; status = 0;
    od
}

active proctype satellite1() {
    chan buffer = [5] of { Message };
    Message msg;
    Message ack;
    // ack message to be sent back to satellites
    Message ack_message;
    ack_message.type = ACK;
    ack_message.src = 0;
    ack_message.dest = 0;
    ack_message.payload = 0;
    // 0: idle, 1: send ack to satellite 2, 2: send ack to satellite 3, 3: wait for grant and send, 4: wait for ack from ground station, 
    // 5: wait for ack from satellite 2, 6: wait for ack from satellite 3, 7: ack received
    int state = 0; 
    run timer(0);
    do
    // Receive or send message (idle)
    :: state == 0 -> if
        :: len(buffer) < 5 -> isl12 ? msg; state = 1;
        :: len(buffer) < 5 -> isl13 ? msg; state = 2;
        :: buffer ? msg -> state = 3;
        fi
    // send ack to satellite 2
    :: state == 1 -> if
        :: grant_isl12 ? _ -> buffer ! msg; state = 0; isl12 ! ack_message;
        :: true -> skip;
        fi
    // send ack to satellite 3
    :: state == 2 -> if
        :: grant_isl13 ? _ -> buffer ! msg; state = 0; isl13 ! ack_message;
        :: true -> skip;
        fi
    // Wait for grant and send
    :: state == 3 -> if
        :: msg.dest == 0 -> if
            :: grant_ground1 ? _ -> state = 4; to_ground1 ! msg; timer_on[0] ! 1;
            :: true -> buffer ! msg; state = 0;
            fi
        :: msg.dest == 1 -> state = 0;
        :: msg.dest == 2 -> if
            :: grant_isl12 ? _ -> state = 5; isl12 ! msg; timer_on[0] ! 1;
            :: true -> buffer ! msg; state = 0;
            fi
        :: msg.dest == 3 -> if
            :: grant_isl13 ? _ -> state = 6; isl13 ! msg; timer_on[0] ! 1;
            :: true -> buffer ! msg; state = 0;
            fi
        fi
    // Wait for ack from ground station
    :: state == 4 -> if
        :: time_out[0] ? _ -> state = 3;
        :: to_ground1 ? ack -> timer_off[0] ! 1; state = 7;
        :: true -> skip;
        fi
    // Wait for ack from satellite 2
    :: state == 5 -> if
        :: time_out[0] ? _ -> state = 3;
        :: isl12 ? ack -> timer_off[0] ! 1; state = 7;
        :: true -> skip;
        fi
    // Wait for ack from satellite 3
    :: state == 6 -> if
        :: time_out[0] ? _ -> state = 3;
        :: isl13 ? ack -> timer_off[0] ! 1; state = 7;
        :: true -> skip;
        fi
    // ack received
    :: state == 7 -> if 
        :: ack.type == ACK -> state = 0;
        :: else -> state = 3;
        fi
    od
}

active proctype satellite2() {
    chan buffer = [5] of { Message };
    Message msg;
    Message ack;
    Message ack_message;
    ack_message.type = ACK;
    ack_message.src = 0;
    ack_message.dest = 0;
    ack_message.payload = 0;
    int state = 0; // 0: idle, 1: send ack to satellite 1, 2: send ack to satellite 3, 3: wait for grant and send, 4: wait for ack from ground station, 5: wait for ack from satellite 1, 6: wait for ack from satellite 3, 7: ack received
    run timer(1);
    do
    :: state == 0 -> if
        :: len(buffer) < 5 -> isl12 ? msg; state = 1;
        :: len(buffer) < 5 -> isl23 ? msg; state = 2;
        :: buffer ? msg -> state = 3;
        fi
    :: state == 1 -> if
        :: grant_isl12 ? _ -> buffer ! msg; state = 0; isl12 ! ack_message;
        :: true -> skip;
        fi
    :: state == 2 -> if
        :: grant_isl23 ? _ -> buffer ! msg; state = 0; isl23 ! ack_message;
        :: true -> skip;
        fi
    :: state == 3 -> if
        :: msg.dest == 0 -> if
            :: grant_ground2 ? _ -> state = 4; to_ground2 ! msg; timer_on[1] ! 1;
            :: true -> buffer ! msg; state = 0;
            fi
        :: msg.dest == 1 -> if
            :: grant_isl12 ? _ -> state = 5; isl12 ! msg; timer_on[1] ! 1;
            :: true -> buffer ! msg; state = 0;
            fi
        :: msg.dest == 2 -> state = 0;
        :: msg.dest == 3 -> if
            :: grant_isl23 ? _ -> state = 6; isl23 ! msg; timer_on[1] ! 1;
            :: true -> buffer ! msg; state = 0;
            fi
        fi
    :: state == 4 -> if
        :: time_out[1] ? _ -> state = 3;
        :: to_ground2 ? ack -> timer_off[1] ! 1; state = 7;
        :: true -> skip;
        fi
    :: state == 5 -> if
        :: time_out[1] ? _ -> state = 3;
        :: isl12 ? ack -> timer_off[1] ! 1; state = 7;
        :: true -> skip;
        fi
    :: state == 6 -> if
        :: time_out[1] ? _ -> state = 3;
        :: isl23 ? ack -> timer_off[1] ! 1; state = 7;
        :: true -> skip;
        fi
    :: state == 7 -> if
        :: ack.type == ACK -> state = 0;
        :: else -> state = 3;
        fi
    od
}

active proctype satellite3() {
    chan buffer = [5] of { Message };
    Message msg;
    Message ack;
    Message ack_message;
    ack_message.type = ACK;
    ack_message.src = 0;
    ack_message.dest = 0;
    ack_message.payload = 0;
    int state = 0; // 0: idle, 1: send ack to satellite 1, 2: send ack to satellite 2, 3: wait for grant and send, 4: wait for ack from ground station, 5: wait for ack from satellite 1, 6: wait for ack from satellite 2, 7: ack received
    run timer(2);
    do
    :: state == 0 -> if
        :: len(buffer) < 5 -> isl13 ? msg; state = 1;
        :: len(buffer) < 5 -> isl23 ? msg; state = 2;
        :: buffer ? msg -> state = 3;
        fi
    :: state == 1 -> if
        :: grant_isl13 ? _ -> buffer ! msg; state = 0; isl13 ! ack_message;
        :: true -> skip;
        fi
    :: state == 2 -> if
        :: grant_isl23 ? _ -> buffer ! msg; state = 0; isl23 ! ack_message;
        :: true -> skip;
        fi
    :: state == 3 -> if
        :: msg.dest == 0 -> if
            :: grant_ground3 ? _ -> state = 4; to_ground3 ! msg; timer_on[2] ! 1;
            :: true -> buffer ! msg; state = 0;
            fi
        :: msg.dest == 1 -> if
            :: grant_isl13 ? _ -> state = 5; isl13 ! msg; timer_on[2] ! 1;
            :: true -> buffer ! msg; state = 0;
            fi
        :: msg.dest == 2 -> if
            :: grant_isl23 ? _ -> state = 6; isl23 ! msg; timer_on[2] ! 1;
            :: true -> buffer ! msg; state = 0;
            fi
        :: msg.dest == 3 -> state = 0;
        fi
    :: state == 4 -> if
        :: time_out[2] ? _ -> state = 3;
        :: to_ground3 ? ack -> timer_off[2] ! 1; state = 7;
        :: true -> skip;
        fi
    :: state == 5 -> if
        :: time_out[2] ? _ -> state = 3;
        :: isl13 ? ack -> timer_off[2] ! 1; state = 7;
        :: true -> skip;
        fi
    :: state == 6 -> if
        :: time_out[2] ? _ -> state = 3;
        :: isl23 ? ack -> timer_off[2] ! 1; state = 7;
        :: true -> skip;
        fi
    :: state == 7 -> if
        :: ack.type == ACK -> state = 0;
        :: else -> state = 3;
        fi
    od
}