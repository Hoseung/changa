#ifndef __CACHEMANAGER_H__
#define __CACHEMANAGER_H__
#include <sys/types.h>
#include <vector>
#include <map>
#include <set>
#include "SFC.h"
#include "GenericTreeNode.h"
#include "charm++.h"

/** NodeCacheEntry represents the entry for a remote 
node that is requested by the chares 
on a processor.
It stores the index of the remote chare from 
which node is to be requested and the local
chares that request it.***/



using namespace std;
//using namespace Tree;
//using namespace SFC;

typedef GenericTreeNode CacheNode;
typedef u_int64_t CacheKey;

class FillNodeMsg;

class CacheEntry{
public:
	CacheKey requestID; // node or particle ID
	int home; // index of the array element that contains this node
	vector<int> requestorVec; // index of the array element that made the request
	vector<BucketGravityRequest *> reqVec;  //request data structure that is different for each requestor

	bool requestSent;
	bool replyRecvd;
	int totalRequests;
	int hits;
	CacheEntry(){
		replyRecvd = false;
		home = -1;
		totalRequests=0;
		hits=0;
		requestSent=false;
	}

};

class NodeCacheEntry : public CacheEntry{
public:
	CacheNode *node;
	
	NodeCacheEntry():CacheEntry(){
		node = NULL;
	}
	~NodeCacheEntry(){
		delete node;
		requestorVec.clear();
		reqVec.clear();
	}
	/// 
	void sendRequest(BucketGravityRequest *);
};	

class ParticleCacheEntry : public CacheEntry{
public:
	GravityParticle *part;
	int num;
	int begin;
	int end;
	ParticleCacheEntry():CacheEntry(){
		part = NULL;
		num=0;
		begin=0;
		end=0;
	}
	~ParticleCacheEntry(){
		delete []part;
		requestorVec.clear();
		reqVec.clear();
	}
	void sendRequest(BucketGravityRequest *);
};

class MapKey {
public:
	CacheKey k;
	int home;
	MapKey(){
		k=0;
		home=0;
	};
	MapKey(CacheKey _k,int _home){
		k = _k;
		home = _home;
	}
};
bool operator<(MapKey lhs,MapKey rhs);

class CacheManager : public Group {
private:
	/* The Cache Table is fully associative 
	A hashtable can be used as well.*/

	map<MapKey,NodeCacheEntry *> nodeCacheTable;
	int reqRecvd;
	int repRecvd;
	bool allReqSent;
	/** counts the total number of nodes requested by all
	the chares on that processor***/
	int totalNodesRequested;
	CacheNode *prototype; ///< @TODO: receive it through cacheSync
	
	int storedNodes;
	unsigned int iterationNo;

	map<MapKey,ParticleCacheEntry*> particleCacheTable;
	int storedParticles;
	bool proxyInitialized; ///< checks if the streaming proxy has been delegated or not
	set<MapKey> outStandingRequests;
	
	void addNodes(int from,CacheNode *node);
	//void addNode(CacheKey key,int from,CacheNode &node);
	/// @brief Check all the TreePiece buckets which requested a node, and call
	/// them back so that they can continue the treewalk.
	void processRequests(CacheNode *node,int from);
	/// @brief Fetches the Node from the correct TreePiece. If the TreePiece
	/// is in the same processor fetch it directly, otherwise send a message
	/// to the remote TreePiece::fillRequestNode
	CacheNode *sendNodeRequest(NodeCacheEntry *e,BucketGravityRequest *);

	public:
	CacheManager();
	~CacheManager(){};

	/** @brief Called by TreePiece to request for a particular node. It can
	 * return the node if it is already present in the cache, or call
	 * sendNodeRequest to get it. Returns null if the Node has to come from
	 * remote.
	*/
	CacheNode *requestNode(int ,int ,CacheKey ,BucketGravityRequest *);
	// Shortcut for the other recvNodes, this receives only one node
	//void recvNodes(CacheKey ,int ,CacheNode &);
	/** @brief Receive the nodes incoming from the remote
	 * TreePiece::fillRequestNode. It imports the nodes into the cache and
	 * process all pending requests.
	 */
	void recvNodes(FillNodeMsg *msg);
	
	GravityParticle *requestParticles(int ,CacheKey ,int ,int ,int ,BucketGravityRequest *);
	void recvParticles(CacheKey ,GravityParticle *,int ,int);
	void cacheSync(unsigned int, GenericTreeNode*);

};

#include "CacheManager.decl.h"
extern CProxy_CacheManager cacheManagerProxy;
#endif

