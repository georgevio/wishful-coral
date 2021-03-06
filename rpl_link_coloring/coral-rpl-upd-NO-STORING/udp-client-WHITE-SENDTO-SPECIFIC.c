#include "contiki.h"
#include "lib/random.h"
#include "sys/ctimer.h"
#include "net/ip/uip.h"
#include "net/ipv6/uip-ds6.h"
#include "net/ip/uip-udp-packet.h"
#include "net/rpl/rpl-conf.h"
#include "net/rpl/rpl.h"

#include "sys/ctimer.h"
#ifdef WITH_COMPOWER
#include "powertrace.h"
#endif
#include <stdio.h>
#include <string.h>

/* Only for TMOTE Sky? */
#include "dev/serial-line.h"
#include "dev/uart0.h"
#include "net/ipv6/uip-ds6-route.h"
#include "node-id.h"
#include "dev/button-sensor.h"

// George to go away from the original server
#define UDP_CLIENT_PORT 6000 //8765
#define UDP_SERVER_PORT 7000 //5678
#define UDP_EXAMPLE_ID  190
// NOTE It works fine with the original sink at the default ports

//#define DEBUG DEBUG_FULL
//George No debug messages
#define DEBUG 0

#include "net/ip/uip-debug.h"

#ifndef PERIOD
#define PERIOD 60
#endif

#define IDOUBLE 8

#define START_INTERVAL		(15 * CLOCK_SECOND)
#define SEND_INTERVAL	(PERIOD * CLOCK_SECOND)
#define SEND_TIME		(random_rand() % (SEND_INTERVAL))
#define MAX_PAYLOAD_LEN		30

static struct uip_udp_conn *client_conn;
static uip_ipaddr_t server_ipaddr; //this is suppose to be the receiver

/* George: Moved here to be treated as global.
 * Remember, in sink it already existed as a variable
 */
rpl_dag_t *d; 

//George RPL current instance to be used in local_repair()
rpl_instance_t *instance;

/*---------------------------------------------------------------------------*/
PROCESS(udp_client_process, "UDP client process");
PROCESS(print_metrics_process, "Printing metrics process");
AUTOSTART_PROCESSES(&udp_client_process,&print_metrics_process);
/*---------------------------------------------------------------------------*/

//from file rpl-conf.h
extern uint8_t rpl_dio_interval_min;
extern uint8_t rpl_dio_interval_doublings;

// George RTT
static uint32_t sent_time=0;
static int rttime; //this will be printed

// George: if they are equal, the message was not lost
static int seq_id;
static int reply;


static void
tcpip_handler(void)
{
  char *str;
  
  //George RTT
  uint32_t timeDIf =0;

  if(uip_newdata()) {
    str = uip_appdata;
    str[uip_datalen()] = '\0';
    reply++;
    
/* George RTT 
 * REMEMBER: You don't need to send the time to the 
 * receiver! Just keep the time the message left, and
 * when it returns, just measure the RTT. 
 * Hence, you don't need to syncronize clocks....
 */
	if(reply == seq_id){ //msg was not lost...
		timeDIf = RTIMER_NOW()-sent_time;
		if (timeDIf < 100000){ //if rtime resets, the number is >>
			//printf("RPL: RTT: %lu\n",timeDIf);
			rttime = timeDIf;
		}
	}
/***************************************************************/
    printf("DATA recvd '%s' (s:%d, r:%d)\n", str, seq_id, reply);
  }
}
/*---------------------------------------------------------------------------*/




static void
send_packet(void *ptr)
{
  char buf[MAX_PAYLOAD_LEN];

// Remember this is better to be enabled in project-conf.h
#ifdef SERVER_REPLY
  uint8_t num_used = 0;
  uip_ds6_nbr_t *nbr;

  PRINTF("Inside sender node, with SERVER_REPLY=1\n");

//const uip_ipaddr_t *uip_ds6_nbr_get_ipaddr(const uip_ds6_nbr_t *nbr);
//uip_ipaddr_t *nbr_ip = nbr->ipaddr;//uip_ds6_nbr_get_ipaddr(*nbr);
  
  nbr = nbr_table_head(ds6_neighbors);
  while(nbr != NULL) {
    nbr = nbr_table_next(ds6_neighbors, nbr);
    num_used++; // number of neighbors

//check this again
    printf("No %d, neighbor: %u\n",num_used,nbr->ipaddr.u8[15]);
  }

  if(seq_id > 0) {
    ANNOTATE("#A r=%d/%d,color=%s,n=%d %d\n", reply, seq_id,
    //printf("#A r=%d/%d,color=%s,n=%d %d\n", reply, seq_id,
             reply == seq_id ? "GREEN" : "RED", 
             uip_ds6_route_num_routes(), num_used);
  }
#endif /* SERVER_REPLY */

  seq_id++;
   				//George Correct address of the server!!!
  PRINTF("DATA send to Server %d 'Hello %d'\n",
         server_ipaddr.u8[sizeof(server_ipaddr.u8) - 1], seq_id);

  // George for RTT
  sent_time = RTIMER_NOW();
  
/********* SENDING THE TIME, ALTHOUGH NOT NEEDED !!! **********/ 
  sprintf(buf, "%lu %d",sent_time, seq_id);
  PRINTF("RPL: Msg No %d, sent at %lu\n",seq_id, sent_time);
  PRINTF("RPL: Msg No %d, buf=%s, sent at %lu\n",seq_id, buf, clock_time());
/*************************************************************/  
  
  
/* George: choosing where to send the message, looks easy:
 * Just change the &server_ipaddr to the address of the 
 * recepient.
 * REMEMBER: You have to alter the recepient to receive 
 * messages, which looks rather more complicated...
 */
    
  //sprintf(buf, "Hello %d from the client", seq_id); //original
  uip_udp_packet_sendto(client_conn, buf, strlen(buf),
                        &server_ipaddr, UIP_HTONS(UDP_SERVER_PORT));
                        
  printf("Sent msg to Server node: ");//%d",server_ipaddr.u8[sizeof(server_ipaddr.u8) - 1]);
  print6addr(&server_ipaddr); // long version
  printf(", msg= %d \n",seq_id);
  
}
/*---------------------------------------------------------------------------*/

static void
print_local_addresses(void)
{
  int i;
  uint8_t state;

  PRINTF("Client IPv6 addresses: ");
  for(i = 0; i < UIP_DS6_ADDR_NB; i++) {
    state = uip_ds6_if.addr_list[i].state;
    if(uip_ds6_if.addr_list[i].isused &&
       (state == ADDR_TENTATIVE || state == ADDR_PREFERRED)) {
      PRINT6ADDR(&uip_ds6_if.addr_list[i].ipaddr);
      PRINTF("\n");
      /* hack to make address "final" */
      if (state == ADDR_TENTATIVE) {
	uip_ds6_if.addr_list[i].state = ADDR_PREFERRED;
      }
    }
  }
}
/*---------------------------------------------------------------------------*/


static void
set_global_address(void)
{
  uip_ipaddr_t ipaddr;

  uip_ip6addr(&ipaddr, UIP_DS6_DEFAULT_PREFIX, 0, 0, 0, 0, 0, 0, 0);
  uip_ds6_set_addr_iid(&ipaddr, &uip_lladdr);
  uip_ds6_addr_add(&ipaddr, 0, ADDR_AUTOCONF);

  uip_ip6addr(&server_ipaddr, UIP_DS6_DEFAULT_PREFIX, 0, 0, 0, 0, 0x00ff, 0xfe00, 2);  // Changed last number from 1 to 2 
  // If you change this number, it communicates fine with the sink

  printf("Server node IP in client: ");
  print6addr(&server_ipaddr);
  printf("\n");
}
/*---------------------------------------------------------------------------*/


PROCESS_THREAD(udp_client_process, ev, data)
{
  static struct etimer periodic;
  static struct ctimer backoff_timer;
#if WITH_COMPOWER
  static int print = 0;
#endif

  PROCESS_BEGIN();

  PROCESS_PAUSE();

  set_global_address();

  PRINTF("UDP client process started nbr:%d routes:%d\n",
         NBR_TABLE_CONF_MAX_NEIGHBORS, UIP_CONF_MAX_ROUTES);

  print_local_addresses();

  /* new connection with remote host */
  client_conn = udp_new(NULL, UIP_HTONS(UDP_SERVER_PORT), NULL); 
  if(client_conn == NULL) {
    printf("No UDP connection available, exiting the process!\n");
    PROCESS_EXIT();
  }
  udp_bind(client_conn, UIP_HTONS(UDP_CLIENT_PORT)); 

  printf("Created custom conn with Server: ");
  printShortaddr(&client_conn->ripaddr);
 // printf(", local addr: ");
  //printShortaddr(&ipaddr);
  //PRINT6ADDR(&client_conn->ripaddr);
  printf(" local/remote port %u/%u\n",
		UIP_HTONS(client_conn->lport), UIP_HTONS(client_conn->rport));

  /* initialize serial line */
  uart0_set_input(serial_line_input_byte);
  serial_line_init();


#if WITH_COMPOWER
  powertrace_sniff(POWERTRACE_ON);
#endif

  etimer_set(&periodic, SEND_INTERVAL);
  while(1) {
    PROCESS_YIELD();
    if(ev == tcpip_event) {
      tcpip_handler();
    }
    
//George ADDED BEHAVIOUR COPIED FROM SINK TO DO LOCAL REPAIRS
    if (ev == sensors_event && data == &button_sensor) {
/***** Trying to resent the instance for this node only ********/		   
			printf("RPL: Initializing LOCAL repair\n");
			rpl_local_repair(instance); // Dont forget to reset rpl
/***************************************************************/
    }

    if(ev == serial_line_event_message && data != NULL) {
      char *str;
      str = data;
      if(str[0] == 'r') {
        uip_ds6_route_t *r;
        uip_ipaddr_t *nexthop;
        uip_ds6_defrt_t *defrt;
        uip_ipaddr_t *ipaddr;
        defrt = NULL;
        if((ipaddr = uip_ds6_defrt_choose()) != NULL) {
          defrt = uip_ds6_defrt_lookup(ipaddr);
        }
        if(defrt != NULL) {
          PRINTF("DefRT: :: -> %02d", defrt->ipaddr.u8[15]);
          PRINTF(" lt:%lu inf:%d\n", stimer_remaining(&defrt->lifetime),
                 defrt->isinfinite);
        } else {
          PRINTF("DefRT: :: -> NULL\n");
        }

        for(r = uip_ds6_route_head();
            r != NULL;
            r = uip_ds6_route_next(r)) {
          nexthop = uip_ds6_route_nexthop(r);
          PRINTF("Route: %02d -> %02d", 
          		r->ipaddr.u8[15], nexthop->u8[15]);
          /* PRINT6ADDR(&r->ipaddr); */
          /* PRINTF(" -> "); */
          /* PRINT6ADDR(nexthop); */
          PRINTF(" lt:%lu\n", r->state.lifetime);

        }
      }
    }

    if(etimer_expired(&periodic)) {
      etimer_reset(&periodic);
      ctimer_set(&backoff_timer, SEND_TIME, send_packet, NULL);

#if WITH_COMPOWER
      if (print == 0) {
	      powertrace_print("#P");
      }
      if (++print == 3) {
	      print = 0;
      }
#endif

    }
  }

  PROCESS_END();
}


/*---------------------------------------------------------------------------*/
//Tryfon's extra for statistics gathering at serial port
PROCESS_THREAD(print_metrics_process, ev, data){
  static struct etimer periodic_timer;
 
  //variable to be in the same printing round for each node
  static int counter=0;

/* NODE COLOR:
 * Remember: you have to use MRHOF2 in order to consider
 * node coloring. 
 * The idea is that, if any parent is RED, it is chosen,
 * Otherwise, normal etx value is considered
 */
  node_color = RPL_DAG_MC_LC_WHITE; //0


  // George current RPL instance: To be used in local_repair()
  instance = d->instance;

/********* Default mode: Imin remains unchanged **********/
  //d->instance->dio_intmin = 12;
  //d->instance->dio_intcurrent = 8;
  
  //George Idouble will be set from outside. Otherwise it is 8
  d->instance->dio_intdoubl = IDOUBLE;
  
  PROCESS_BEGIN();
  PRINTF("Printing Client Metrics...\n");

  SENSORS_ACTIVATE(button_sensor);

  // 60*CLOCKS_SECOND for rm090 should print every one (1) min
  etimer_set(&periodic_timer, 60*CLOCK_SECOND);

  while(1) {
    PROCESS_WAIT_EVENT_UNTIL(etimer_expired(&periodic_timer));
    etimer_reset(&periodic_timer);

    //printf("R:%d, Leaf MODE: %d\n",counter,rpl_get_mode());
	 
	 printf("R:%d, RTT:%d\n",counter,rttime);
    
    counter++; //new round of stats
  }
   PROCESS_END();
}
/*---------------------------------------------------------------------------*/

