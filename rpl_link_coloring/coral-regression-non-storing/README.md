node sender-node.c can send messages-and receive responce if any- to any other node. Just change the last number in the static void sender(). You can easily add a for loop to send to more than one. You obviously have to alter the rtt to an array style to hold all RTT.

node root-node.c is receiving messages-and send them back. If you want to disable the receiving/sending, disable the line 
PROCESS(unicast_receiver_process, "Unicast server receiver process");
in 
AUTOSTART_PROCESSES(&unicast_receiver_process, &button_server_process);

it also has the functionalities: 
1. You can change the Objective Function by clicking the button. Right now, the 1st time it calls MRHOF2, the second time it calls MRHOF, and all over. You can obviously change the behaviour inside 
PROCESS_THREAD(button_server_process, ev, data)

2. It changes the Objective Function in second 20 and back to the original in second 40. Obviously you can disable or alter those...
REMEMBER: You have to call a global repair after changing the OF (RPL doesnot do this by default). Also you have to call a local repair in the node you want to alter behaviour immediately.

Dont forget this, in order to make reasonable rounds (the same all over the experiment)
  // 60*CLOCK_SECOND should print for RM090 every one (1)  min
  etimer_set(&periodic_timer, 60*CLOCK_SECOND);
  while(1) {
    PROCESS_WAIT_EVENT_UNTIL(etimer_expired(&periodic_timer));
    etimer_reset(&periodic_timer);


receiver-node.c is also receiving and sending back-if chosen by the sender. The receiver() process is identical with the sink's. It is wise to call a local_repair() also whenever the OF changes (this should be investigated nevertheless).--------------

neutral-node.c and neutral-node-RED.c are identical: they DO NOT receive/send messages. The RED one has the node_color=RED, so it will be chosen if MRHOF2 is enabled. 

Control Experiment: All nodes in a row, see only one another. So each one
has one father and one son. RTT is increasing away from the sink.

Experiment 0: Storing mode, 1 sink (S) receiving, 2 red nodes (r), 
one white (w), one sender (s). ALL FOUR SEND.
Experiment starts AND ENDS with MRHOF, hence,
THERE MUST BE NO CHANGE IN ALL RTTs.

Experiment 1: Storing mode, 1 sink (S) receiving, 2 red nodes (r), 
one white (w), one sender (s). Experiment starts with MRHOF for 20min. 
The sender sends s->w->S for 20min. Then change OF=MRHOF2, call global_repair
in sink, and local_repair in s. In minute=40, back to MRHOF with same
procedures (global/local repairs).

Experiment 2: Storing mode, 1 sink (S) receiving, 2 red nodes (r), 
one white (w), one sender (s). ALL FOUR SEND.
Experiment starts with MRHOF for 20min. 
The sender sends s->w->S for 20min. Then change OF=MRHOF2, call global_repair
in sink, and local_repair in s. In minute=40, back to MRHOF with same
procedures (global/local repairs).

Experiment 3: Storing Mode, Point to Point: Node 5 is sending, No 2 is receiving
With MRHOF, the path is 5->4->1->2, hence a big RTT. Switching to MRHOF2, Node 5
connects to Node 3 as a prefered parent (Node 3 is red), hence the RTT drops significally.
We noticed that in order for both points (sender and receiver) to establish immediately 
the new path, we had to trigger a local repair for  both. This way, we not only "force"
the two nodes to communicate immediately via Node 3, i.e. the new path, but also,
we don't "disturb" the whole network.
