Author: Robert Bärhold
Date: 18.05.2015

These scripts distrubes XtreemFS over allocated cumulus nodes.

First, please adjust the env.sh. Afterwards, use "xtreemfsCumulus.sh" to start
and stop a distributed environment. It can also clone a git repository (clone)
or clean (cleanup) the local xtreemfs folder for the current cumulus job on each
allocated cumulus node.


HELP:

(1) How to allocate cumulus nodes:

  Use the following statement, whereas -N* referes to the number of nodes,
  which should be allocated.
  
    # salloc -N1 -p CSR -A csr --exclusive


(2) Something went wrong stopping the server. How to fix a broken server?

  Connect to the specific node via the following statement:
  
    # srun -N1-1 --nodelist=cumu-n[xx] --pty bash
  
  If you want to stop a running server, locate the PID file and call "kill", e.g.:
  
    # cat /local/xtreemfs/xxxxx/MRC.pid
    12345
    # kill 12345 
  
  or short:
  
    # kill $(</local/xtreemfs/xxxxx/MRC.pid)
  
  If the current job folder has been deleted already, use the following 
  statement to retrieve the process id and kill it.
  
    # ps -ax | grep java
    # kill 12345
    
 (3) On the cumulus nodes are still traces due to an error.
 
  Call "cleanup" or connect to each server (comp. (2)) and remove the folder by
  
    # rm -r /local/xtreemfs