#define N_NODES 3 //3 in lift 1 referee
#define LIFT_VALUE 5
chan succ[N_NODES] = [10] of { mtype }
chan pred[N_NODES] = [10] of { mtype }
chan ref[N_NODES] = [10] of { mtype }
chan to_referee = [10] of { mtype, chan }
mtype = {promise, status, pend, commit, void, signature, null}
byte state[N_NODES + 1] //plus ref
int balanceSuccDelta[N_NODES] = 0
int balancePredDelta[N_NODES] = 0
typedef Action {
  mtype type;
  int dest;
  int src;
}
//This is a variable used only to compare with coq properties
//It is hidden from the state because it is a write only variable
hidden Action actions[N_NODES*2] = 0
hidden int actionIndex = 0
bool gotRefResult[N_NODES] = false

#define ORIGINATOR 0
#define RELAY_1 1
#define RELAY_2 2
#define REFEREE 3
#define NO_LIFT 0
#define GOOD 1
#define VOID 2
#define PEND 3
#define CALL 4

inline sendToPred(message, id) {
    //TODO: make some messages fail
    atomic {
    if
    :: true ->
        printf("%d Sending %e to Pred\n", id, message)
        byte prev;
        prev = (id+N_NODES-1)%N_NODES; //find who it goes to
        succ[prev]!message; //put it in their succ box (if they are my pred I am their succ)
        actions[actionIndex].type = message
        actions[actionIndex].dest = prev
        actions[actionIndex].src = id
        actionIndex = actionIndex + 1
    :: true ->
        printf("%d Message to Pred Failed\n", id)
    fi
    }
}

inline sendToSucc(message, id) {
    atomic {
    if
    :: true -> //Ssend the message
        printf("%d Sending %e to Succ\n", id, message)
        byte next;
        next = (id+1)%N_NODES; //find who it goes to
        pred[next]!message; //put it in their pred box (if they are my succ I am their pred)
        actions[actionIndex].type = message
        actions[actionIndex].dest = next
        actions[actionIndex].src = id
        actionIndex = actionIndex + 1
    :: true -> //The message Failed to send
        printf("%d Message to Succ Failed\n", id)
    fi
    }
}

inline sendToReferee(message, id) {
    printf("%d Sending %e to Ref\n", id, message)
    to_referee!message(ref[id]); //put it in the referee's in box with a return channel for the response
}

proctype originator() {
  bool statusUnresponded //flag to only send referee one status request (the ref will always eventually respond so this is sufficient)
  state[ORIGINATOR] = NO_LIFT
  statusUnresponded = false
  do
  :: (state[ORIGINATOR] == NO_LIFT) ->
    printf("Originator: Initiating Lift\n")
    true -> sendToPred(promise, ORIGINATOR)
    state[ORIGINATOR] = PEND
  :: (state[ORIGINATOR] == PEND && !statusUnresponded) ->
    printf("Originator: Requesting Status\n")
    statusUnresponded = true
    true -> sendToReferee(status, ORIGINATOR)
    state[ORIGINATOR] = PEND
  :: (ref[ORIGINATOR]?[pend]) -> //clear pend from chan in any state
    printf("Originator: Received Pend\n")
    statusUnresponded = false
    ref[ORIGINATOR]?pend
  :: (state[ORIGINATOR] == PEND && succ[ORIGINATOR]?[promise]) ->
    printf("Originator: Committing\n")
    succ[ORIGINATOR]?promise -> sendToReferee(commit, ORIGINATOR)
    state[ORIGINATOR] = CALL
  :: ((state[ORIGINATOR] == PEND) && ref[ORIGINATOR]?[void]) ->
      printf("Originator: Invalidating\n")
      statusUnresponded = false
      ref[ORIGINATOR]?void
      //DONT FORWARD STATUS REQUESTS
      //sendToSucc(void, ORIGINATOR)
      gotRefResult[ORIGINATOR] = true
      state[ORIGINATOR] = VOID
      break
  :: ((state[ORIGINATOR] == CALL) && ref[ORIGINATOR]?[void]) ->
      printf("Originator: Invalidating\n")
      statusUnresponded = false
      ref[ORIGINATOR]?void ->
      sendToSucc(void, ORIGINATOR)
      state[ORIGINATOR] = VOID
      break
  :: (state[ORIGINATOR] == CALL && ref[ORIGINATOR]?[signature]);
      printf("Originator: Recieved Signature\n")
      statusUnresponded = false
      ref[ORIGINATOR]?signature ->
      sendToSucc(signature, ORIGINATOR)
      balanceSuccDelta[ORIGINATOR] = balanceSuccDelta[ORIGINATOR] + LIFT_VALUE
      state[ORIGINATOR] = GOOD
  :: (state[ORIGINATOR] == 1 && pred[ORIGINATOR]?[signature]);
      printf("Originator: Recieved Signature, Lift Complete\n")
      pred[ORIGINATOR]?signature ->
      balancePredDelta[ORIGINATOR] = balancePredDelta[ORIGINATOR] - LIFT_VALUE
      state[ORIGINATOR] = GOOD
      break
  od

}

proctype referee() {
  chan returnChan
  state[REFEREE] = NO_LIFT
  do
  :: (state[REFEREE] == NO_LIFT && to_referee?[status(returnChan)]) ->
      printf("Referee: Replying Pend\n")
      to_referee?status(returnChan) ->
      returnChan!pend
  :: (state[REFEREE] == NO_LIFT && to_referee?[status(returnChan)]) ->
      printf("Referee: Ruling and Replying Void\n")
      to_referee?status(returnChan) ->
      returnChan!void
      state[REFEREE] = 2
  :: (state[REFEREE] == NO_LIFT && to_referee?[commit(returnChan)]) ->
      printf("Referee: Ruling and Replying to Commit Void\n")
      to_referee?commit(returnChan) ->
      returnChan!void
      state[REFEREE] = 2
  :: (state[REFEREE] == NO_LIFT && to_referee?[commit(returnChan)]) ->
      printf("Referee: Ruling and Replying to Commit Signature\n")
      to_referee?commit(returnChan) ->
      returnChan!signature
      state[REFEREE] = 1
  :: (state[REFEREE] == 1 && to_referee?[status(returnChan)]) ->
      printf("Referee: Replying from cache Signature\n")
      to_referee?status(returnChan) ->
      returnChan!signature
  :: (state[REFEREE] == 2 && to_referee?[status(returnChan)]) ->
      printf("Referee: Replying from cache Void\n")
      to_referee?status(returnChan) ->
      returnChan!void
  :: (state[REFEREE] == 2 && to_referee?[commit(returnChan)]) ->
      printf("Referee: Replying to Commit from cache Void\n")
      to_referee?commit(returnChan) ->
      returnChan!void
  :: (timeout) -> break
  od
}

proctype relay_1() {

  bool statusUnresponded
  state[RELAY_1] = NO_LIFT
  statusUnresponded = false
  do
  :: (state[RELAY_1] == NO_LIFT && succ[RELAY_1]?[promise]) ->
    printf("Relay 1: Received Promise\n")
    succ[RELAY_1]?promise -> sendToPred(promise, RELAY_1)
    state[RELAY_1] = PEND
  :: (state[RELAY_1] == PEND && !statusUnresponded) ->
    printf("Relay 1: Requesting Status\n")
    true -> sendToReferee(status, RELAY_1)
    statusUnresponded = true
    state[RELAY_1] = PEND
  :: (ref[RELAY_1]?[pend]) -> //clear pend from chan in any state
    printf("Relay 1: Received Pend\n")
    statusUnresponded = false
    ref[RELAY_1]?pend
  :: (state[RELAY_1] == PEND && ref[RELAY_1]?[void]) ->
    statusUnresponded = false
    ref[RELAY_1]?void ->
      printf("Relay 1: Invalidating\n")
      //Don't forward if got from ref
      //sendToSucc(void, RELAY_1)
      gotRefResult[RELAY_1] = true
      state[RELAY_1] = VOID
      break
  :: (state[RELAY_1] == PEND && pred[RELAY_1]?[void]) ->
    pred[RELAY_1]?void ->
      printf("Relay 1: Invalidating\n")
      sendToSucc(void, RELAY_1)
      state[RELAY_1] = VOID
      break
  :: (state[RELAY_1] == PEND && ref[RELAY_1]?[signature]);
      printf("Relay 1: Received Signature from Ref\n")
      ref[RELAY_1]?signature ->
      balancePredDelta[RELAY_1] = balancePredDelta[RELAY_1] - LIFT_VALUE
      //sendToSucc(signature, RELAY_1)
      //Don't forward if got from ref
      balanceSuccDelta[RELAY_1] = balanceSuccDelta[RELAY_1] + LIFT_VALUE
      gotRefResult[RELAY_1] = true
      state[RELAY_1] = GOOD
      break
  :: (state[RELAY_1] == PEND && pred[RELAY_1]?[signature]);
      printf("Relay 1: Received Signature\n")
      pred[RELAY_1]?signature ->
      balancePredDelta[RELAY_1] = balancePredDelta[RELAY_1] - LIFT_VALUE
      sendToSucc(signature, RELAY_1)
      balanceSuccDelta[RELAY_1] = balanceSuccDelta[RELAY_1] + LIFT_VALUE
      state[RELAY_1] = GOOD
      break
  od

}

proctype relay_2() {

  bool statusUnresponded
  state[RELAY_2] = NO_LIFT
  statusUnresponded = false
  do
  :: (state[RELAY_2] == NO_LIFT && succ[RELAY_2]?[promise]) ->
    printf("Relay 2: Received Promise\n")
    succ[RELAY_2]?promise -> sendToPred(promise, RELAY_2)
    state[RELAY_2] = PEND
  :: (state[RELAY_2] == PEND && !statusUnresponded) ->
    printf("Relay 2: Requesting Status\n")
    true -> sendToReferee(status, RELAY_2)
    statusUnresponded = true
    state[RELAY_2] = PEND
  :: (ref[RELAY_2]?[pend]) -> //clear pend from chan in any state
    printf("Relay 2: Received Pend\n")
    statusUnresponded = false
    ref[RELAY_2]?pend
  :: (state[RELAY_2] == PEND && ref[RELAY_2]?[void]) ->
    statusUnresponded = false
    ref[RELAY_2]?void ->
      printf("Relay 2: Invalidating\n")
      //Don't forward if got from ref
      //sendToSucc(void, RELAY_2)
      gotRefResult[RELAY_2] = true
      state[RELAY_2] = VOID
      break
  :: (state[RELAY_2] == PEND && pred[RELAY_2]?[void]) ->
    pred[RELAY_2]?void ->
      printf("Relay 2: Invalidating\n")
      sendToSucc(void, RELAY_2)
      state[RELAY_2] = VOID
      break
  :: (state[RELAY_2] == PEND && ref[RELAY_2]?[signature]);
      printf("Relay 2: Received Signature from Ref\n")
      ref[RELAY_2]?signature ->
      balancePredDelta[RELAY_2] = balancePredDelta[RELAY_2] - LIFT_VALUE
      //sendToSucc(signature, RELAY_2)
      //Don't forward if got from ref
      balanceSuccDelta[RELAY_2] = balanceSuccDelta[RELAY_2] + LIFT_VALUE
      gotRefResult[RELAY_2] = true
      state[RELAY_2] = GOOD
      break
  :: (state[RELAY_2] == PEND && pred[RELAY_2]?[signature]);
      printf("Relay 2: Received Signature\n")
      pred[RELAY_2]?signature ->
      balancePredDelta[RELAY_2] = balancePredDelta[RELAY_2] - LIFT_VALUE
      sendToSucc(signature, RELAY_2)
      balanceSuccDelta[RELAY_2] = balanceSuccDelta[RELAY_2] + LIFT_VALUE
      state[RELAY_2] = GOOD
      break
  od

}

init {
  atomic {
    int i;
    for (i : 1 .. N_NODES*2) {
      actions[i-1].type = null
      actions[i-1].src = -1
      actions[i-1].dest = -1
    }
    run originator()
    run relay_1()
    run relay_2()
    run referee()
  }
}

#define fair (eventually (state[REFEREE] == GOOD || state[REFEREE] == VOID))

ltl fairPathExists {(always (! fair))} // should fail

ltl p1 {always eventually (fair implies ( (state[ORIGINATOR] == GOOD || state[ORIGINATOR] == VOID)
                                       && (state[RELAY_1] == GOOD      || state[RELAY_1] == VOID)
                                       && (state[RELAY_2] == GOOD      || state[RELAY_2] == VOID)
                                       && (state[REFEREE] == GOOD    || state[REFEREE] == VOID)))}

ltl p2 {always eventually (fair implies ( (state[ORIGINATOR] == state[RELAY_1] && state[RELAY_1] == state[RELAY_2] && state[RELAY_2] == state[REFEREE])))}

ltl p3 {always eventually (fair implies ( (balanceSuccDelta[ORIGINATOR] + balancePredDelta[ORIGINATOR] >= 0)
                                       && (balanceSuccDelta[RELAY_1] + balancePredDelta[RELAY_1] >= 0)
                                       && (balanceSuccDelta[RELAY_2] + balancePredDelta[RELAY_2] >= 0)
                                       ))}

ltl p4 {always eventually (fair implies ((balanceSuccDelta[ORIGINATOR] ==  balancePredDelta[RELAY_1])
                                      && (balanceSuccDelta[RELAY_1] == balancePredDelta[RELAY_2])
                                      && (balanceSuccDelta[RELAY_2] == balancePredDelta[ORIGINATOR])
                                      ))}

//ADJUSTED COQ TO Make message to originator not required
#define size_eq_3 (eventually (state[ORIGINATOR] != NO_LIFT*/ && state[RELAY_1] != NO_LIFT && state[RELAY_2] != NO_LIFT))

ltl size_3_path_exists {(always (! size_eq_3))} // should fail
ltl fair_size_3_path_exists {(always (! (fair && size_eq_3)))} // should fail

/*
    (
      exists (m : nat),
      forall (n : nat),
      ((n >= m) -> ((S n) < size) ->
      In (Send (Z.of_nat (S n)) (Z.of_nat n) Commit) acts /\
      In (Receive (Z.of_nat (n)) Commit) acts /\
      ~In (SendRef (Z.of_nat (n))) acts /\
      ~In (ReceiveRef (Z.of_nat (n))) acts
      ) 
      /\ 
      ((n < m) -> (n < size) ->
      ~In (Send (Z.of_nat (S n)) (Z.of_nat n) Commit) acts /\
      ~In (Receive (Z.of_nat (n)) Commit) acts /\
      In (SendRef (Z.of_nat (n))) acts /\
      In (ReceiveRef (Z.of_nat (n))) acts
      ) 
    )
    /\
    (
    forall (n : nat),
    (S n) < size ->
    In (Send (Z.of_nat (n)) (Z.of_nat (S n)) Promise) acts /\
    In (Receive (Z.of_nat (n)) Promise) acts
    ) /\ In (Send 0 (-1) Commit) acts.


*/

#define actionValid(index) (actions[index].type != null)
#define actionAtNum(num, message, srcId, destId) (actions[num].type == message && actions[num].src == srcId && actions[num].dest == destId)

#define first_promise actionAtNum(0, promise, ORIGINATOR, RELAY_2)

#define r1_pn(num) actionAtNum(num, promise, RELAY_2, RELAY_1)
#define Relay_1_receives_promise r1_pn(1) // this could be valid in any index but it is always 1
#define O_pn(num) actionAtNum(num, promise, RELAY_1, ORIGINATOR)

#define relay_1_receives_commit (actionAtNum(3, void, ORIGINATOR, RELAY_1) || actionAtNum(3, signature, ORIGINATOR, RELAY_1) || gotRefResult[RELAY_1] == true)

#define relay_2_receives_commit (actionAtNum(4, void, RELAY_1, RELAY_2) || actionAtNum(4, signature, RELAY_1, RELAY_2) || gotRefResult[RELAY_2] == true)

ltl has_required_actions {always ((fair && size_eq_3) implies eventually (first_promise && Relay_1_receives_promise && relay_1_receives_commit && relay_2_receives_commit))}

#define actionsNotEqual(index1, index2) (always ((fair && size_eq_3)) -> (actions[index1].type == null || actions[index2].type == null) || actions[index1].type != actions[index2].type || actions[index1].src != actions[index2].src || actions[index1].dest != actions[index2].dest)

ltl has_no_duplicate_receives_0a {always ((fair & size_eq_3) implies (
  actionsNotEqual(0, 1) && 
  actionsNotEqual(0, 2) 
  ))
}
ltl has_no_duplicate_receives_0b {always ((fair & size_eq_3) implies (
  actionsNotEqual(0, 3) && 
  actionsNotEqual(0, 4) && 
  actionsNotEqual(0, 5)
  ))
}
ltl has_no_duplicate_receives_1 {always ((fair & size_eq_3) implies (
  actionsNotEqual(1, 2) && 
  actionsNotEqual(1, 3) && 
  actionsNotEqual(1, 4) && 
  actionsNotEqual(1, 5)
  ))
}
ltl has_no_duplicate_receives_2 {always ((fair & size_eq_3) implies (
  actionsNotEqual(2, 3) && 
  actionsNotEqual(2, 4) && 
  actionsNotEqual(2, 5)
  ))
}
ltl has_no_duplicate_receives_3 {always ((fair & size_eq_3) implies (
  actionsNotEqual(3, 4) && 
  actionsNotEqual(3, 5)
  ))
}
ltl has_no_duplicate_receives_4 {always ((fair & size_eq_3) implies (
  actionsNotEqual(4, 5)
  ))
}

#define phase_seq(index1, index2) (actionValid(index1) && actionValid(index2)) implies (actions[index1].type != actions[index2].type implies (actions[index1].type == promise && (actions[index2].type == void || actions[index2].type == signature)))
ltl phase_sequence_correct {always eventually (phase_seq(0, 1) && phase_seq(1, 2) && phase_seq(2, 3) && phase_seq(3, 4) && phase_seq(4, 5))}
