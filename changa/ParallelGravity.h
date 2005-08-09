/** @file ParallelGravity.h
 */
 
#ifndef PARALLELGRAVITY_H
#define PARALLELGRAVITY_H

#include <string>
#include <map>
#include <vector>
#include <algorithm>

#include "pup_stl.h"
#include "ComlibManager.h"

#include "Vector3D.h"
#include "tree_xdr.h"
#include "SFC.h"
#include "TreeNode.h"
#include "GenericTreeNode.h"
#include "Interval.h"

using namespace Tree;

enum DomainsDec {
  SFC_dec,
  Oct_dec,
  ORB_dec
};

inline void operator|(PUP::er &p,DomainsDec &d) {
  int di;
  if (p.isUnpacking()) {
    p | di;
    d = (DomainsDec)di;
  } else {
    di = (int)d;
    p | di;
  }
}

#include "GravityParticle.h"

#include "CacheManager.h"
#include "ParallelGravity.decl.h"

extern int verbosity;
extern bool _cache;
extern int _cacheLineDepth;
extern unsigned int _yieldPeriod;
extern DomainsDec domainDecomposition;
extern GenericTrees useTree;

class dummyMsg : public CMessage_dummyMsg{
public:
int val;
};

/********************************************/
class piecedata : public CMessage_piecedata {
public:
	int CellInteractions;
	int ParticleInteractions;
	int MACChecks;
	double totalmass;
	CkCallback cb;
	
	piecedata():CellInteractions(0),ParticleInteractions(0),MACChecks(0),totalmass(0.0) { }
	void modifypiecedata(int cell,int particle,int mac,double mass){ 
		CellInteractions += cell;
		ParticleInteractions += particle;
		MACChecks += mac;
		totalmass += mass;
	}
	void reset(){ CellInteractions=0;ParticleInteractions=0;MACChecks=0;totalmass=0.0; }
	void setcallback(CkCallback& cback) { cb = cback; }
	CkCallback& getcallback() { return cb; }
};
/********************************************/

class RequestNodeMsg : public CMessage_RequestNodeMsg {
 public:
  int retIndex;
  int depth;
  Tree::NodeKey key;
  unsigned int reqID;

  RequestNodeMsg(int r, int d, Tree::NodeKey k, unsigned int req) : retIndex(r), depth(d), key(k), reqID(req) {}
};

class FillNodeMsg : public CMessage_FillNodeMsg {
 public:
  int owner;
  //int count;
  char *nodes;

  FillNodeMsg(int index) : owner(index) { }

  /*
  static FillNodeMsg::alloc(int msgnum, size_t sz, int *sizes, int pb) {
    int offsets[2];
    offsets[0] = ALIGN8(sz - 1); // -1 because we take out the "char nodes[1]"
    if(sizes==0) offsets[1] = offsets[0];
    else offsets[1] = offsets[0] + ALIGN8(sizes[0]);
    FillNodeMsg *newmsg = (FillNodeMsg *) CkAllocMsg(msgnum, offsets[1], pb);
    return (void *) newmsg;
  }
  */
};

class Main : public Chare {
	std::string basefilename;
	CProxy_TreePiece pieces;
	unsigned int numTreePieces;
	double theta;
	unsigned int bucketSize;
	unsigned int printBinaryAcc;
public:
		
	Main(CkArgMsg* m);

	/**
	 * Principal method which does all the coordination of the work.
	 * It is threaded, so it suspends while waiting for the TreePieces to
	 * perform the task. It calls TreePieces for: 1) load, 2) buildTree, 3)
	 * calculateGravity and startlb for the desired number of iterations.
	 */
	void nextStage();
};

class TreePiece : public CBase_TreePiece {
 private:
	unsigned int numTreePieces;
	/// @brief Used to inform the mainchare that the requested operation has
	/// globally finished
	CkCallback callback;
	unsigned int myNumParticles;
	GravityParticle* myParticles;
	GravityParticle* leftBoundary;
	GravityParticle* rightBoundary;
	/***************************/
	double piecemass;
	int cnt;
	int packed;
	/*************************/
	unsigned int numSplitters;
	SFC::Key* splitters;
	CProxy_TreePiece pieces;
	CProxy_TreePiece streamingProxy;
	std::string basefilename;
	OrientedBox<float> boundingBox;
	FieldHeader fh;
	bool started;
	unsigned iterationNo;
	//TreeStuff::TreeNode* root;
	GenericTreeNode* root;
	unsigned int boundaryNodesPending;
	//SFCTreeNode tempNode;
	/// Opening angle
	double theta;

	/// Map between Keys and TreeNodes, used to get a node from a key
	NodeLookupType nodeLookupTable;

	/// @if ALL

	/// unused - SEND VERSION
	unsigned int mySerialNumber;

	/// @endif

	/// Number of particles which are still traversing the tree
	u_int64_t myNumParticlesPending;
	u_int64_t myNumCellInteractions;
	u_int64_t myNumParticleInteractions;
	u_int64_t myNumMACChecks;
	u_int64_t myNumProxyCalls;
	u_int64_t myNumProxyCallsBack;

	/// @if ALL

	/// this was used when particles were traversing the tree (and not buckets)
	u_int64_t nextParticle;

	/// @endif

	/// Size of bucketList, total number of buckets present
	unsigned int numBuckets;
	/// Used to start the computation for all buckets, one after the other
	unsigned int currentBucket;
	/// Same as myNumCellInteractions, only restricted to cached nodes
	int cachecellcount;
	/// List of all the node-buckets in this TreePiece
	std::vector<GenericTreeNode *> bucketList;
	/// @brief Used as a placeholder while traversing the tree and computing
	/// forces. This should not exist in the cache version since all its
	/// information is duplicate from the correspondent TreeNode (in
	/// bucketList), and myParticles.
	/// @todo Eliminate the usage of this in the cache walk
	BucketGravityRequest *bucketReqs;
	
	/// @if ALL

	// all these are used only in the SEND VERSION
	typedef std::map<unsigned int, GravityRequest> UnfilledRequestsType;
	UnfilledRequestsType unfilledRequests;
	typedef std::map<unsigned int, BucketGravityRequest> UnfilledBucketRequestsType;
	UnfilledBucketRequestsType unfilledBucketRequests;

	/// @endif

	/// Pointer to the instance of the local cache
	CacheManager *localCache;
	int countIntersects;
	int countHits;

	/*
	SFCTreeNode* lookupLeftChild(SFCTreeNode* node);
	SFCTreeNode* lookupRightChild(SFCTreeNode* node);
	*/

	/// convert a key to a node using the nodeLookupTable
	inline GenericTreeNode *keyToNode(const Tree::NodeKey);

 public:

	// Recursive call to build the subtree with root "node", and SFC bounded by the two particles
	//void buildOctTree(GenericTreeNode* node, GravityParticle* leftParticle, GravityParticle* rightParticle);

	/// Recursive call to build the subtree with root "node", level
	/// specifies the level at which "node" resides inside the tree
	void buildOctTree(GenericTreeNode* node, int level);
	void calculateRemoteMoments(GenericTreeNode* node);
	void checkTree(GenericTreeNode* node);
	bool nodeOwnership(const GenericTreeNode *const node, int &firstOwner, int &lastOwner);
	//bool nodeOwnership(SFCTreeNode* node, unsigned int* designatedOwner = 0, unsigned int* numOwners = 0, unsigned int* firstOwner = 0, unsigned int* lastOwner = 0);

	/// @if ALL

	/// unused - SEND VERSION - Recursive tree walk over a tree
	void walkTree(GenericTreeNode* node, GravityRequest& req);
	/// unused - SEND VERSION - Sending the next particle for computation
	void startNextParticle();

	/// @endif

	/** @brief Initial walk through the tree. It will continue until local
	 * nodes are found (excluding those coming from the cache). If non-local
	 * cached nodes are found cachedWalkBucketTree is called. When the
	 * treewalk is finished it stops and cachedWalkBucketTree will continue
	 * with the incoming nodes.
	 */
	void walkBucketTree(GenericTreeNode* node, BucketGravityRequest& req);
	/** @brief Start the treewalk for the next bucket among those belonging
	 * to me. The buckets are simply ordered in a vector.
	 */
	void startNextBucket();
	/** @brief Start a full step of bucket computation, it sends a message
	 * to trigger nextBucket which will loop over all the buckets.
	 */
	void doAllBuckets();
	/// Copy one node into the position passed be "tmp" (used to fill a request)
	//void copySFCTreeNode(SFCTreeNode &tmp,SFCTreeNode *node);
	/// Recursive function to copy nodes into the filling request (to be returned to the requester)
	//void prefixCopyNode(SFCTreeNode *node,Key lookupKey,Key *cacheKeys,SFCTreeNode *cacheNodes,int *count,int depth);
	void rebuildSFCTree(GenericTreeNode *node,GenericTreeNode *parent,int *);
	
public:
	
	TreePiece(unsigned int numPieces) : numTreePieces(numPieces), pieces(thisArrayID), streamingProxy(thisArrayID), started(false), root(0) {
	//CkPrintf("[%d] TreePiece created\n",thisIndex);
	    // ComlibDelegateProxy(&streamingProxy);
		if(_cache){	
		  localCache = cacheManagerProxy.ckLocalBranch();
		}	
		iterationNo=0;
		usesAtSync=CmiTrue;
		countIntersects=0;
		/****************/
		piecemass = 0.0;
		packed=0;
		cnt=0;
		/****************/
	}
	
	TreePiece(CkMigrateMessage* m) { 
		usesAtSync=CmiTrue;
	}
	~TreePiece() {
		delete[] myParticles;
		delete[] splitters;
	}
	
	void load(const std::string& fn, const CkCallback& cb);

	/// Charm entry point to build the tree (called by Main), calls collectSplitters
	void buildTree(int bucketSize, const CkCallback& cb);

	/// Collect the boundaries of all TreePieces, and trigger the real treebuild
	void collectSplitters(CkReductionMsg* m);
	/// Real tree build, independent of other TreePieces; calls the recursive buildTree
	void startOctTreeBuild(CkReductionMsg* m);
	
	void acceptBoundaryNodeContribution(const Tree::NodeKey key, const int numParticles, const MultipoleMoments& moments);
	void acceptBoundaryNode(const Tree::NodeKey key, const int numParticles, const MultipoleMoments& moments);

	/// @if ALL

	/// unused - SEND VERSION
	bool openCriterion(GenericTreeNode *node, GravityRequest& req);

	/// @endif

	bool openCriterionBucket(GenericTreeNode *node,
				 BucketGravityRequest& req);

	/// @if ALL

	/// unused (only for correctness check) - Used to perform n^2 (particle-particle) computation
	void calculateGravityDirect(const CkCallback& cb);
	/// unused (only for correctness check) - Filler for n^2 (particle-particle) computation
	void fillRequestDirect(GravityRequest req);
	/// unused (only for correctness check) - Receive incoming particle for computation n^2
	void receiveGravityDirect(const GravityRequest& req);

	/// unused - Treewalk one particle at a time
	void calculateGravityTree(double t, const CkCallback& cb);
	/// unused - Fill the request, almost identical to fillRequestBucketTree
	void fillRequestTree(GravityRequest req);	
	/// unused - Receive incoming data for particle tree walk
	void receiveGravityTree(const GravityRequest& req);

	/// unused - SEND VERSION - Return to the requester the data (typically the cache manager)
	void fillRequestBucketTree(BucketGravityRequest req);
	/// unused - SEND VERSION - callback where the data requested to another TreePiece will come back.
	void receiveGravityBucketTree(const BucketGravityRequest& req);

	/// @endif

	/// @brief Main entry point to start gravity computation
	void calculateGravityBucketTree(double t, const CkCallback& cb);

	/// @brief Retrieve the remote node, goes through the cache if present
	GenericTreeNode* requestNode(int remoteIndex, Tree::NodeKey lookupKey,
				 BucketGravityRequest& req);
	/// @brief Receive a request for Nodes from a remote processor, copy the
	/// data into it, and send back a message.
	void fillRequestNode(RequestNodeMsg *msg);
	/** @brief Receive the node from the cache as following a previous
	 * request which returned NULL, and continue the treewalk of the bucket
	 * which requested it with this new node.
	*/
	void receiveNode(GenericTreeNode &node, unsigned int reqID);
	/// Just and inline version of receiveNode
	void receiveNode_inline(GenericTreeNode &node, unsigned int reqID);
	/// @brief Find the key in the KeyTable, and copy the node over the passed pointer
	/// @todo Could the node copy be avoided?
	const GenericTreeNode* lookupNode(Tree::NodeKey key);

	/// @if ALL

	/// unused - highly inefficient version that requests one single particle
	GravityParticle* requestParticle(int remoteIndex, int iPart,
					 BucketGravityRequest& req);
	/// unused - highly inefficient version that returns one single particle
	void fillRequestParticle(int retIndex, int iPart,
				 BucketGravityRequest& req);
	/// unused - highly inefficient version that receives one single particle
	void receiveParticle(GravityParticle part, BucketGravityRequest& req);

	/// @endif

	/// @brief Check if we have done with the treewalk on a specific bucket,
	/// and if we have, check also if we are done with all buckets
	inline void finishBucket(int iBucket);
	/** @brief Routine which does the tree walk on non-local nodes. It is
	 * called back for every incoming node (which are those requested to the
	 * cache during previous treewalks), and continue the treewalk from
	 * where it had been interrupted. It will possibly made other remote
	 * requests. It is also called tro walkBucketTree when a non-local node
	 * is found.
	 */
	void cachedWalkBucketTree(GenericTreeNode* node,
				  BucketGravityRequest& req);
	GravityParticle *requestParticles(SFC::Key &key,int remoteIndex,int begin,int end,BucketGravityRequest &req);
	void fillRequestParticles(SFC::Key key,int retIndex, int begin,int end,
				  unsigned int reqID);
	void receiveParticles(GravityParticle *part,int num,
			      unsigned int reqID);
	void receiveParticles_inline(GravityParticle *part,int num,
				     unsigned int reqID);
			  
	void startlb(CkCallback &cb);
	void ResumeFromSync();

	void outputAccelerations(OrientedBox<double> accelerationBox, const std::string& suffix, const CkCallback& cb);
	void outputAccASCII(OrientedBox<double> accelerationBox, const std::string& suffix, const CkCallback& cb);
	void outputStatistics(Interval<unsigned int> macInterval, Interval<unsigned int> cellInterval, Interval<unsigned int> particleInterval, Interval<unsigned int> callsInterval, double totalmass, const CkCallback& cb);
	void outputRelativeErrors(Interval<double> errorInterval, const CkCallback& cb);

/*******************ADDED*******************/
	void getPieceValues(piecedata *totaldata);
/*******************************************/	
        /** @brief Entry method used to split the processing of all the buckets
         * in small pieces. It call startNextBucket a _yieldPeriod number of
         * times, and then it returns to the scheduler after enqueuing a message
         * for itself.
	 */
        void nextBucket(dummyMsg *m);

	void report(const CkCallback& cb);
	void printTree(GenericTreeNode* node, ostream& os);	
	void pup(PUP::er& p);
};

void printTree(GenericTreeNode* node, ostream& os) ;
bool compBucket(GenericTreeNode *ln,GenericTreeNode *rn);
#endif //PARALLELGRAVITY_H
