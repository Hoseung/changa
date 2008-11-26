#ifdef _WIN32
#define NOMINMAX
#endif

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <float.h>
#include "wr.h"
// #include <cutil.h>

#include "cuda_runtime.h"

#define BLOCK_SIZE 128

extern workRequestQueue *wrQueue;
extern void **devBuffers;
extern cudaStream_t kernel_stream;

__constant__ constantData[88];

void DataManagerTransfer(CudaMultipoleMoments *moments, int nMoments, CompactPartData *compactParts, int nCompactParts, int bufferID) {

	int numBlocks = (int) ceilf((float)n/BLOCK_SIZE);

	//workRequest *transferKernel = (workRequest*) malloc(sizeof(workRequest));
	workRequest transferKernel;
	dataInfo *momentBuffer, *partCoreBuffer;

	transferKernel.dimGrid = dim3(numBlocks);
	transferKernel.dimBlock = dim3(BLOCK_SIZE);
	transferKernel.smemSize = 0;

	transferKernel.nBuffers = DM_TRANSFER_NBUFFERS;

	/* schedule two buffers for transfer to the GPU */
	transferKernel.bufferInfo = (dataInfo *) malloc(transferKernel.nBuffers * sizeof(dataInfo));

	momentBuffer = &(transferKernel.bufferInfo[POST_PREFETCH_MOMENTS]);
	momentBuffer->bufferID = bufferID+POST_PREFETCH_MOMENTS;
	momentBuffer->transferToDevice = YES;
	momentBuffer->transferFromDevice = NO;
	momentBuffer->freeBuffer = NO;
	momentBuffer->hostBuffer = moments;
	momentBuffer->size = (nMoments) * sizeof(CudaMultipoleMoments);

	partCoreBuffer = &(topKernel.bufferInfo[POST_PREFETCH_PARTICLE_CORES]);
	partCoreBuffer->bufferID = bufferID+POST_PREFETCH_PARTICLE_CORES;
	partCoreBuffer->transferToDevice = YES;
	partCoreBuffer->transferFromDevice = NO;
	partCoreBuffer->freeBuffer = NO;
	partCoreBuffer->hostBuffer = compactParts;
	partCoreBuffer->size = (nCompactParts)*sizeof(CompactPartData);

	transferKernel.callbackFn = 0;
	transferKernel.id = DM_TRANSFER;
	transferKernel.executing = 0;
	enqueue(wrQueue, &transferKernel);

}

void TreePieceCellListDataTransferLocal(CellListData *data){
	int numBlocks = (int) ceilf((float)n/BLOCK_SIZE);

	workRequest gravityKernel;
	dataInfo *buffer, *partCoreBuffer;

	// FIXME - size properly
	gravityKernel.dimGrid = dim3(numBlocks);
	gravityKernel.dimBlock = dim3(BLOCK_SIZE);
	gravityKernel.smemSize = 0;

	gravityKernel.nBuffers = TP_GRAVITY_LOCAL_NBUFFERS;

	/* schedule buffers for transfer to the GPU */
	gravityKernel.bufferInfo = (dataInfo *) malloc(gravityKernel.nBuffers * sizeof(dataInfo));

	TreePieceCellListDataTransferBasic(data, &gravityKernel);

	gravityKernel.callbackFn = 0;
	gravityKernel.id = TP_GRAVITY_LOCAL;
	gravityKernel.executing = 0;
	enqueue(wrQueue, &gravityKernel);
}

void TreePieceCellListDataTransferRemote(CellListData *data){
	int numBlocks = (int) ceilf((float)n/BLOCK_SIZE);

	workRequest gravityKernel;
	dataInfo *buffer, *partCoreBuffer;

	// FIXME - size properly
	gravityKernel.dimGrid = dim3(numBlocks);
	gravityKernel.dimBlock = dim3(BLOCK_SIZE);
	gravityKernel.smemSize = 0;

	gravityKernel.nBuffers = TP_NODE_GRAVITY_REMOTE_NBUFFERS;

	/* schedule buffers for transfer to the GPU */
	gravityKernel.bufferInfo = (dataInfo *) malloc(gravityKernel.nBuffers * sizeof(dataInfo));

	TreePieceCellListDataTransferBasic(data, &gravityKernel);

	gravityKernel.callbackFn = 0;
	gravityKernel.id = TP_GRAVITY_REMOTE;
	gravityKernel.executing = 0;
	enqueue(wrQueue, &gravityKernel);
}

void TreePieceCellListDataTransferRemoteResume(CellListData *data, CudaMultipoleMoments *missedMoments, int numMissedMoments){
	int numBlocks = (int) ceilf((float)n/BLOCK_SIZE);

	//workRequest *gravityKernel = (workRequest*) malloc(sizeof(workRequest));
	workRequest gravityKernel;
	dataInfo *buffer, *partCoreBuffer;

	// FIXME - size properly
	gravityKernel.dimGrid = dim3(numBlocks);
	gravityKernel.dimBlock = dim3(BLOCK_SIZE);
	gravityKernel.smemSize = 0;

	gravityKernel.nBuffers = TP_NODE_GRAVITY_REMOTE_RESUME_NBUFFERS;

	/* schedule buffers for transfer to the GPU */
	gravityKernel.bufferInfo = (dataInfo *) malloc(gravityKernel.nBuffers * sizeof(dataInfo));

	TreePieceCellListDataTransferBasic(data, &gravityKernel);

	buffer = &(gravityKernel.bufferInfo[MISSED_MOMENTS]);
	// FIXME - needs to be unique?
	buffer->bufferID = bufferID+MISSED_MOMENTS;
	buffer->transferToDevice = YES;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = YES;
	buffer->hostBuffer = missedMoments;
	buffer->size = (numMissedMoments) * sizeof(int);

	gravityKernel.callbackFn = 0;
	gravityKernel.id = TP_GRAVITY_REMOTE_RESUME;
	gravityKernel.executing = 0;
	enqueue(wrQueue, &gravityKernel);
}

void TreePieceCellListDataTransferBasic(CellListData *data, workRequest *gravityKernel){
	dataInfo *buffer;
	int numInteractions = data->numInteractions;
	int numBucketsPlusOne = data->numBucketsPlusOne;
	ILCell *cellList = data->cellList;
	int *cellListBucketMarkers = data->partListBucketMarkers;
	int *bucketStarts = data->bucketStarts;
	int *bucketSizes = data->bucketSizes;

	buffer = &(gravityKernel->bufferInfo[ILCELL]);
	// FIXME - needs to be unique?
	buffer->bufferID = bufferID+ILCELL;
	buffer->transferToDevice = YES;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = YES;
	buffer->hostBuffer = cellList;
	buffer->size = (numInteractions) * sizeof(ILCell);

	buffer = &(gravityKernel->bufferInfo[NODE_INTLIST_BUCKET_MARKERS]);
	// FIXME - needs to be unique?
	buffer->bufferID = bufferID+NODE_INTLIST_BUCKET_MARKERS;
	buffer->transferToDevice = YES;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = YES;
	buffer->hostBuffer = cellListBucketMarkers;
	buffer->size = (numBucketsPlusOne) * sizeof(int);

	buffer = &(gravityKernel->bufferInfo[NODE_INTLIST_BUCKET_STARTS]);
	// FIXME - needs to be unique?
	buffer->bufferID = bufferID+NODE_INTLIST_BUCKET_STARTS;
	buffer->transferToDevice = YES;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = YES;
	buffer->hostBuffer = bucketStarts;
	buffer->size = (numBucketsPlusOne-1) * sizeof(int);

	buffer = &(gravityKernel->bufferInfo[NODE_INTLIST_BUCKET_SIZES]);
	// FIXME - needs to be unique?
	buffer->bufferID = bufferID+NODE_INTLIST_BUCKET_SIZES;
	buffer->transferToDevice = YES;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = YES;
	buffer->hostBuffer = bucketSizes;
	buffer->size = (numBucketsPlusOne-1) * sizeof(int);
}

void TreePiecePartListDataTransferLocal(PartListData *data){
	int numBlocks = (int) ceilf((float)n/BLOCK_SIZE);

	workRequest gravityKernel;
	dataInfo *buffer, *partCoreBuffer;

	// FIXME - size properly
	gravityKernel.dimGrid = dim3(numBlocks);
	gravityKernel.dimBlock = dim3(BLOCK_SIZE);
	gravityKernel.smemSize = 0;

	gravityKernel.nBuffers = TP_GRAVITY_LOCAL_NBUFFERS;

	/* schedule buffers for transfer to the GPU */
	gravityKernel.bufferInfo = (dataInfo *) malloc(gravityKernel.nBuffers * sizeof(dataInfo));

	TreePiecePartListDataTransferBasic(data, gravityKernel);

	gravityKernel.callbackFn = 0;
	gravityKernel.id = TP_PART_GRAVITY_LOCAL;
	gravityKernel.executing = 0;
	enqueue(wrQueue, &gravityKernel);
}

void TreePiecePartListDataTransferRemote(PartListData *data, CompactPartData *missedParts, int numMissedParts){
	int numBlocks = (int) ceilf((float)n/BLOCK_SIZE);

	//workRequest *gravityKernel = (workRequest*) malloc(sizeof(workRequest));
	workRequest gravityKernel;
	dataInfo *buffer, *partCoreBuffer;

	// FIXME - size properly
	gravityKernel.dimGrid = dim3(numBlocks);
	gravityKernel.dimBlock = dim3(BLOCK_SIZE);
	gravityKernel.smemSize = 0;

	gravityKernel.nBuffers = TP_PART_GRAVITY_REMOTE_NBUFFERS;

	/* schedule buffers for transfer to the GPU */
	gravityKernel.bufferInfo = (dataInfo *) malloc(gravityKernel.nBuffers * sizeof(dataInfo));

	TreePiecePartListDataTransferBasic(data, gravityKernel);

	buffer = &(gravityKernel.bufferInfo[MISSED_PARTS]);
	// FIXME - needs to be unique?
	buffer->bufferID = bufferID+MISSED_PARTS;
	buffer->transferToDevice = YES;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = YES;
	buffer->hostBuffer = missedParts;
	buffer->size = (numMissedParts) * sizeof(int);

	gravityKernel.callbackFn = 0;
	gravityKernel.id = TP_PART_GRAVITY_REMOTE;
	gravityKernel.executing = 0;
	enqueue(wrQueue, &gravityKernel);
}

void TreePiecePartListDataTransferRemoteResume(PartListData *data, CompactPartData *missedParts, int numMissedParts){
	int numBlocks = (int) ceilf((float)n/BLOCK_SIZE);

	//workRequest *gravityKernel = (workRequest*) malloc(sizeof(workRequest));
	workRequest gravityKernel;
	dataInfo *buffer, *partCoreBuffer;

	// FIXME - size properly
	gravityKernel.dimGrid = dim3(numBlocks);
	gravityKernel.dimBlock = dim3(BLOCK_SIZE);
	gravityKernel.smemSize = 0;

	gravityKernel.nBuffers = TP_PART_GRAVITY_REMOTE_RESUME_NBUFFERS;

	/* schedule buffers for transfer to the GPU */
	gravityKernel.bufferInfo = (dataInfo *) malloc(gravityKernel.nBuffers * sizeof(dataInfo));

	TreePiecePartListDataTransferBasic(data, gravityKernel);

	buffer = &(gravityKernel.bufferInfo[MISSED_PARTS]);
	// FIXME - needs to be unique?
	buffer->bufferID = bufferID+MISSED_PARTS;
	buffer->transferToDevice = YES;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = YES;
	buffer->hostBuffer = missedParts;
	buffer->size = (numMissedParts) * sizeof(int);

	gravityKernel.callbackFn = 0;
	gravityKernel.id = TP_PART_GRAVITY_REMOTE_RESUME;
	gravityKernel.executing = 0;
	enqueue(wrQueue, &gravityKernel);
}

void TreePiecePartListDataTransferBasic(PartListData *data, workRequest *gravityKernel){
	dataInfo *buffer;

	int numInteractions = data->numInteractions;
	int numBucketsPlusOne = data->numBucketsPlusOne;
	ILPart *partList = data->partList;
	int *partListBucketMarkers = data->partListBucketMarkers;
	int *bucketStarts = data->bucketStarts;
	int *bucketSizes = data->bucketSizes;

	buffer = &(gravityKernel->bufferInfo[ILPART]);
	// FIXME - needs to be unique?
	buffer->bufferID = bufferID+ILPART;
	buffer->transferToDevice = YES;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = YES;
	buffer->hostBuffer = partList;
	buffer->size = (numInteractions) * sizeof(ILPart);

	buffer = &(gravityKernel->bufferInfo[PART_INTLIST_BUCKET_MARKERS]);
	// FIXME - needs to be unique?
	buffer->bufferID = bufferID+PART_INTLIST_BUCKET_MARKERS;
	buffer->transferToDevice = YES;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = YES;
	buffer->hostBuffer = partListBucketMarkers;
	buffer->size = (numBucketsPlusOne) * sizeof(int);

	buffer = &(gravityKernel->bufferInfo[PART_INTLIST_BUCKET_STARTS]);
	// FIXME - needs to be unique?
	buffer->bufferID = bufferID+PART_INTLIST_BUCKET_STARTS;
	buffer->transferToDevice = YES;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = YES;
	buffer->hostBuffer = bucketStarts;
	buffer->size = (numBucketsPlusOne-1) * sizeof(int);

	buffer = &(gravityKernel->bufferInfo[PART_INTLIST_BUCKET_SIZES]);
	// FIXME - needs to be unique?
	buffer->bufferID = bufferID+PART_INTLIST_BUCKET_SIZES;
	buffer->transferToDevice = YES;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = YES;
	buffer->hostBuffer = bucketSizes;
	buffer->size = (numBucketsPlusOne-1) * sizeof(int);
}

/*
__global__ void EwaldTopKernel(GravityParticleData *particleTable) {
*/

/* kernels:

TP_GRAVITY_LOCAL,
TP_GRAVITY_REMOTE,
TP_GRAVITY_REMOTE_RESUME,
TP_PART_GRAVITY_LOCAL,
TP_PART_GRAVITY_REMOTE,
TP_PART_GRAVITY_REMOTE_RESUME

 */

extern void DeleteHostMoments(CudaMultipoleMoments *array);
extern void DeleteHostParticles(CompactPartData *array);
static boolean dmTransferDone = NO;

void kernelSelect(workRequest *wr) {

  switch (wr->id) {
  case DM_TRANSFER:
	  dmTransferDone = YES;
	  DeleteHostMoments(wr->bufferInfo[POST_PREFETCH_MOMENTS].hostBuffer);
	  DeleteHostParticles(wr->bufferInfo[POST_PREFETCH_PARTICLE_CORES].hostBuffer);
	  break;

  case TP_GRAVITY_LOCAL:
	  // FIXME - fix arguments
	  if(dmTransferDone){
		  //GravityKernel<<<wr->dimGrid, wr->dimBlock, wr->smemSize, kernel_stream>>>
		  //((GravityParticleData *)devBuffers[wr->bufferInfo[PARTICLE_TABLE].bufferID],
			//(EwtData *)devBuffers[wr->bufferInfo[EWALD_TABLE].bufferID]);
	  }
	  else{
		  // fix buffer transfer flags and re-enqueue
		  NoTransferEnqueueNodeBasic(wr);
	  }
    break;

  case TP_PART_GRAVITY_LOCAL:
  	  // FIXME - fix arguments
  	  if(dmTransferDone){
  		  //GravityKernel<<<wr->dimGrid, wr->dimBlock, wr->smemSize, kernel_stream>>>
  		  //((GravityParticleData *)devBuffers[wr->bufferInfo[PARTICLE_TABLE].bufferID],
  			//(EwtData *)devBuffers[wr->bufferInfo[EWALD_TABLE].bufferID]);
  	  }
  	  else{
  		  // fix buffer transfer flags and re-enqueue
  		  NoTransferEnqueuePartBasic(wr);
  	  }
      break;

  case TP_GRAVITY_REMOTE:
	  if(dmTransferDone){
		  // invoke kernel
	  }
	  else{
		  // fix buffer transfer flags and re-enqueue
		  NoTransferEnqueueNodeBasic(wr);
	  }
	  break;

  case TP_PART_GRAVITY_REMOTE:
	  if(dmTransferDone){
		  // invoke kernel
	  }
	  else{
		  // fix buffer transfer flags and re-enqueue
		  NoTransferEnqueuePartBasic(wr);

	  }
	  break;

	  // FIXME - remote resume for parts and nodes
	  // after that, set callbacks
	  // finally, do book-keeping, remaining mindful of the lastBucketComplete flag in the state

  default:
    printf("error: id %d not valid\n", wr->id);
    break;
  }
}

void NoTransferEnqueueNodeBasic(workRequest *gravityKernel){
	dataInfo *buffer;

	// all buffer transfer parameters set to NO because there already exists a workRequest that will do all
	// of this
	workRequest *newGravityKernel = (workRequest*) malloc(sizeof(workRequest));
	*newGravityKernel = *gravityKernel;

	buffer = &(newGravityKernel->bufferInfo[ILCELL]);
	buffer->transferToDevice = NO;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = NO;

	buffer = &(newGravityKernel->bufferInfo[NODE_INTLIST_BUCKET_MARKERS]);
	buffer->transferToDevice = NO;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = NO;

	buffer = &(newGravityKernel->bufferInfo[NODE_INTLIST_BUCKET_STARTS]);
	buffer->transferToDevice = NO;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = NO;

	buffer = &(newGravityKernel->bufferInfo[NODE_INTLIST_BUCKET_SIZES]);
	buffer->transferToDevice = NO;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = NO;

	enqueue(wrQueue, newGravityKernel);
}

void NoTransferEnqueuePartBasic(workRequest *gravityKernel){
	dataInfo *buffer;

	// all buffer transfer parameters set to NO because there already exists a workRequest that will do all
	// of this
	workRequest *newGravityKernel = (workRequest*) malloc(sizeof(workRequest));
	*newGravityKernel = *gravityKernel;

	buffer = &(newGravityKernel->bufferInfo[ILPART]);
	buffer->transferToDevice = NO;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = NO;

	buffer = &(newGravityKernel->bufferInfo[PART_INTLIST_BUCKET_MARKERS]);
	buffer->transferToDevice = NO;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = NO;

	buffer = &(newGravityKernel->bufferInfo[PART_INTLIST_BUCKET_STARTS]);
	buffer->transferToDevice = NO;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = NO;

	buffer = &(newGravityKernel->bufferInfo[PART_INTLIST_BUCKET_SIZES]);
	buffer->transferToDevice = NO;
	buffer->transferFromDevice = NO;
	buffer->freeBuffer = NO;

	enqueue(wrQueue, gravityKernel);
}

/*
 * Kernels
 */

#define GROUP(t)  ((t)/MAX_THREADS_PER_GROUP)
#define GROUP_INDEX(t) ((t)%MAX_THREADS_PER_GROUP)

__global__ void nodeGravityComputation(
		CompactPartData *particleCores,
		VariablePartData *particleVars,
		CudaMultipoleMoments *moments,
		ILCell *ils,
		int numInteractions,
		int *ilmarks,
		int *bucketStarts,
		int *bucketSizes,
		int numBucketsPlusOne){

  // each thread has its own storage for these
  __shared__ CudaVector3D acc[THREADS_PER_BLOCK];
  __shared__ cudatype pot[THREADS_PER_BLOCK];
  __shared__ CudaMultipoleMoments m[THREADS_PER_BLOCK];

  // to store a few particles in shared memory 
  __shared__ CompactPartData cached_particle_cores[PART_CACHE_SIZE];
  // in case PART_CACHE_SIZE < bucketSize, need this extra
  __shared__ CompactPartData shared_particle_core;


  // each block is given a bucket to compute
  // each thread in the block computes an interaction of a particle with a node
  // threads must iterate through the interaction lists and sync.
  // then, block leader (first rank in each block) reduces the forces and commits 
  // values to global memory.
  int bucket = blockIdx.x;
  int start = ilmarks[bucket];
  int end = ilmarks[bucket+1];
  int bucketSize = bucketSizes[bucket];
  int bucketStart = bucketStarts[bucket];
  int thread = threadIdx.x;

  // length of cell interaction list for this bucket
  int llen = end-start;

  CudaVector3D r;
  cudatype rsq;
  cudatype twoh, a, b, c, d;

#ifdef __DEVICE_EMULATION__
  if(blockIdx.x == 0){
    //printf("t: %d, blen: %d, llen: %d\n", threadIdx.x, blen, llen);
    //printf("group: %d, particle: %d, ngroups: %d, groupSize: %d\n", group, particle, ngroups, groupSize);
  }
#endif


  for(int node = thread; node < llen; node += THREADS_PER_BLOCK){
#ifdef __DEVICE_EMULATION__
    if(blockIdx.x == 0){
      //printf("t: %d, particle: %d, node: %d\n", threadIdx.x, particle, node);
      //printf("shared_moments[%d] = moments[%d]\n", threadIdx.x, ils[ilmarks[bucket]+node].index);
    }
#endif
    // FIXME - ought to keep ilmarks[blockIdx.x] in a register
    // all threads in a group access different mem locations
    // however, threads accessing the same node in different
    // groups access the same memory location
    // therefore, there ought to be 8 accesses for every 4 groups
    // FIXME - can this be reduced somehow?

    m[thread] = moments[ils[ilmarks[bucket]+node].index];
    int offsetID = ils[ilmarks[bucket]+node].offsetID;

    for(int particle = 0; particle < bucketSize; particle++){
      
      acc[thread].x = 0;
      acc[thread].y = 0;
      acc[thread].z = 0;
      pot[thread] = 0;
      
      // true or false for all threads in block, so no divergence
      if(particle < PART_CACHE_SIZE){
        // use cached_particle_cores
          
        r.x = cached_particle_cores[particle].position.x -
                        ((((offsetID >> 22) & 0x7)-3)*fperiod + m[thread].cm.x);
        r.y = cached_particle_cores[particle].position.y -
                        ((((offsetID >> 25) & 0x7)-3)*fperiod + m[thread].cm.y);
        r.z = cached_particle_cores[particle].position.z -
                        ((((offsetID >> 28) & 0x7)-3)*fperiod + m[thread].cm.z);

        rsq = r.x*r.x + r.y*r.y + r.z*r.z;        
        twoh = m[thread].soft + cached_particle_cores[particle].soft;
        if(rsq != 0){
          cudatype dir = 1.0/sqrt(rsq);
          // SPLINEQ(dir, rsq, twoh, a, b, c, d);
          // expansion of function below:
          cudatype u,dih;
          if (rsq < twoh*twoh) {
            dih = 2.0/twoh;
            u = dih/dir;
            if (u < 1.0) {
              a = dih*(7.0/5.0 - 2.0/3.0*u*u + 3.0/10.0*u*u*u*u
            		 - 1.0/10.0*u*u*u*u*u);
              b = dih*dih*dih*(4.0/3.0 - 6.0/5.0*u*u + 1.0/2.0*u*u*u);
              c = dih*dih*dih*dih*dih*(12.0/5.0 - 3.0/2.0*u);
              d = 3.0/2.0*dih*dih*dih*dih*dih*dih*dir;
            }
            else {
              a = -1.0/15.0*dir + dih*(8.0/5.0 - 4.0/3.0*u*u + u*u*u
                          - 3.0/10.0*u*u*u*u + 1.0/30.0*u*u*u*u*u);
              b = -1.0/15.0*dir*dir*dir + dih*dih*dih*(8.0/3.0 - 3.0*u
                          + 6.0/5.0*u*u - 1.0/6.0*u*u*u);
              c = -1.0/5.0*dir*dir*dir*dir*dir + 3.0*dih*dih*dih*dih*dir
            	+ dih*dih*dih*dih*dih*(-12.0/5.0 + 1.0/2.0*u);
              d = -dir*dir*dir*dir*dir*dir*dir
            	+ 3.0*dih*dih*dih*dih*dir*dir*dir
            	- 1.0/2.0*dih*dih*dih*dih*dih*dih*dir;
            }
          }
          else {
            a = dir;
            b = a*a*a;
            c = 3.0*b*a*a;
            d = 5.0*c*a*a;
          }
     
          cudatype qirx = m[thread].xx*r.x + m[thread].xy*r.y + m[thread].xz*r.z;
          cudatype qiry = m[thread].xy*r.x + m[thread].yy*r.y + m[thread].yz*r.z;
          cudatype qirz = m[thread].xz*r.x + m[thread].yz*r.y + m[thread].zz*r.z;
          cudatype qir = 0.5*(qirx*r.x + qiry*r.y + qirz*r.z);
          cudatype tr = 0.5*(m[thread].xx + m[thread].yy + m[thread].zz);
          cudatype qir3 = b*m[thread].totalMass + d*qir - c*tr;

          pot[thread] -= m[thread].totalMass * a + c*qir - b*tr;

          acc[thread].x -= qir3*r.x - c*qirx;
          acc[thread].y -= qir3*r.y - c*qiry;
          acc[thread].z -= qir3*r.z - c*qirz;
      }
      else{
        if(thread == 0){
          // load shared_particle_core and use
          shared_particle_core = particleCores[bucketStart+particle];
        }
          
        r.x = shared_particle_core.position.x -
                        ((((offsetID >> 22) & 0x7)-3)*fperiod + m[thread].cm.x);
        r.y = shared_particle_cores.position.y -
                        ((((offsetID >> 25) & 0x7)-3)*fperiod + m[thread].cm.y);
        r.z = shared_particle_core.position.z -
                        ((((offsetID >> 28) & 0x7)-3)*fperiod + m[thread].cm.z);

        rsq = r.x*r.x + r.y*r.y + r.z*r.z;        
        twoh = m[thread].soft + shared_particle_core.soft;
        if(rsq != 0){
          cudatype dir = 1.0/sqrt(rsq);
          // SPLINEQ(dir, rsq, twoh, a, b, c, d);
          // expansion of function below:
          cudatype u,dih;
          if (rsq < twoh*twoh) {
            dih = 2.0/twoh;
            u = dih/dir;
            if (u < 1.0) {
              a = dih*(7.0/5.0 - 2.0/3.0*u*u + 3.0/10.0*u*u*u*u
            		 - 1.0/10.0*u*u*u*u*u);
              b = dih*dih*dih*(4.0/3.0 - 6.0/5.0*u*u + 1.0/2.0*u*u*u);
              c = dih*dih*dih*dih*dih*(12.0/5.0 - 3.0/2.0*u);
              d = 3.0/2.0*dih*dih*dih*dih*dih*dih*dir;
            }
            else {
              a = -1.0/15.0*dir + dih*(8.0/5.0 - 4.0/3.0*u*u + u*u*u
                          - 3.0/10.0*u*u*u*u + 1.0/30.0*u*u*u*u*u);
              b = -1.0/15.0*dir*dir*dir + dih*dih*dih*(8.0/3.0 - 3.0*u
                          + 6.0/5.0*u*u - 1.0/6.0*u*u*u);
              c = -1.0/5.0*dir*dir*dir*dir*dir + 3.0*dih*dih*dih*dih*dir
            	+ dih*dih*dih*dih*dih*(-12.0/5.0 + 1.0/2.0*u);
              d = -dir*dir*dir*dir*dir*dir*dir
            	+ 3.0*dih*dih*dih*dih*dir*dir*dir
            	- 1.0/2.0*dih*dih*dih*dih*dih*dih*dir;
            }
          }
          else {
            a = dir;
            b = a*a*a;
            c = 3.0*b*a*a;
            d = 5.0*c*a*a;
          }
     
          cudatype qirx = m[thread].xx*r.x + m[thread].xy*r.y + m[thread].xz*r.z;
          cudatype qiry = m[thread].xy*r.x + m[thread].yy*r.y + m[thread].yz*r.z;
          cudatype qirz = m[thread].xz*r.x + m[thread].yz*r.y + m[thread].zz*r.z;
          cudatype qir = 0.5*(qirx*r.x + qiry*r.y + qirz*r.z);
          cudatype tr = 0.5*(m[thread].xx + m[thread].yy + m[thread].zz);
          cudatype qir3 = b*m[thread].totalMass + d*qir - c*tr;

          pot[thread] -= m[thread].totalMass * a + c*qir - b*tr;

          acc[thread].x -= qir3*r.x - c*qirx;
          acc[thread].y -= qir3*r.y - c*qiry;
          acc[thread].z -= qir3*r.z - c*qirz;
        }// end if rsq != 0
      }// end else (particle >= PART_CACHE_SIZE)
      
      __syncthreads();
      // all threads have computed their portion of the forces
      // time to add forces up
      
      cudatype sum = 0.0;
      if(thread == 0){
        for(int i = 0; i < THREADS_PER_BLOCK; i++){
          sum += acc[i].x;
        }
        particleVars[bucketStart+particle].a.x += sum;
        
        sum = 0;
        for(int i = 0; i < THREADS_PER_BLOCK; i++){
          sum += acc[i].y;
        }
        particleVars[bucketStart+particle].a.y += sum;

        sum = 0;
        for(int i = 0; i < THREADS_PER_BLOCK; i++){
          sum += acc[i].z;
        }
        particleVars[bucketStart+particle].a.z += sum;
        
        sum = 0;
        for(int i = 0; i < THREADS_PER_BLOCK; i++){
          sum += pot[i];
        }
        particleVars[bucketStart+particle].potential += sum;
      }
    }// end for each particle
  }// end for each thread (node)
}

__global__ void particleGravityComputation(
                                   CompactPartData *particleCores,
                                   VariablePartData *particleVars,
                                   ILPart *ils,
		                   int numInteractions,
                                   int *ilmarks,
		                   int *bucketStarts,
		                   int *bucketSizes,
		                   int numBucketsPlusOne,
                                   int x, cudatype fperiod){

  // shared_source_cores: interactions (source particles)
  // shared_target_cores: bucket particles (target particles)

  // replace shared_source_cores with source_cores
  // replace shared_target_cores with cached_target_cores/shared_target_core
  // each thread has its own storage for these
  __shared__ CudaVector3D acc[THREADS_PER_BLOCK];
  __shared__ cudatype pot[THREADS_PER_BLOCK];
  __shared__ CompactPartData source_cores[THREADS_PER_BLOCK];

  // to store a few particles in shared memory 
  __shared__ CompactPartData cached_target_cores[PART_CACHE_SIZE];
  // in case PART_CACHE_SIZE < bucketSize, need this extra
  __shared__ CompactPartData shared_target_core;


  // each block is given a bucket to compute
  // each thread in the block computes an interaction of a particle with a node
  // threads must iterate through the interaction lists and sync.
  // then, block leader (first rank in each block) reduces the forces and commits 
  // values to global memory.
  int bucket = blockIdx.x;
  int start = ilmarks[bucket];
  int end = ilmarks[bucket+1];
  int bucketSize = bucketSizes[bucket];
  int bucketStart = bucketStarts[bucket];
  int thread = threadIdx.x;

  // length of cell interaction list for this bucket
  int llen = end-start;

  CudaVector3D r;
  cudatype rsq;
  cudatype twoh, a, b;

#ifdef __DEVICE_EMULATION__
  if(blockIdx.x == 0){
    //printf("t: %d, blen: %d, llen: %d\n", threadIdx.x, blen, llen);
    //printf("group: %d, particle: %d, ngroups: %d, groupSize: %d\n", group, particle, ngroups, groupSize);
  }
#endif


  for(int source = thread; source < llen; source += THREADS_PER_BLOCK){
#ifdef __DEVICE_EMULATION__
    if(blockIdx.x == 0){
      //printf("t: %d, particle: %d, node: %d\n", threadIdx.x, particle, node);
      //printf("shared_moments[%d] = moments[%d]\n", threadIdx.x, ils[ilmarks[bucket]+node].index);
    }
#endif

    source_cores[thread] = particleCores[ils[ilmarks[bucket]+source].index];
    int oid = ils[ilmarks[bucket]+source].off;

    for(int target = 0; target < bucketSize; target++){
      
      acc[thread].x = 0;
      acc[thread].y = 0;
      acc[thread].z = 0;
      pot[thread] = 0;
      
      // true or false for all threads in block, so no divergence
      if(target < PART_CACHE_SIZE){
        // use cached_particle_cores
        r.x = (((oid >> 22) & 0x7)-3)*fperiod +
                source_cores[thread].position.x -
                cached_target_cores[target].position.x;

        r.y = (((oid >> 25) & 0x7)-3)*fperiod +
                source_cores[thread].position.y -
                cached_target_cores[target].position.y;

        r.z = (((oid >> 28) & 0x7)-3)*fperiod +
                source_cores[thread].position.z -
                cached_target_cores[target].position.z;

        rsq = r.x*r.x + r.y*r.y + r.z*r.z;
        twoh = source_cores[thread].soft + cached_target_cores[target].soft;
        if(rsq != 0){
          //SPLINE(rsq, twoh, a, b);
          //SPLINE(r2, twoh, a, b);
          //expanded below:
	  cudatype r1, u,dih,dir;
	  r1 = sqrt(rsq);
	  if (r1 < (twoh)) {
		dih = 2.0/(twoh);
		u = r1*dih;
		if (u < 1.0) {
			a = dih*(7.0/5.0 - 2.0/3.0*u*u + 3.0/10.0*u*u*u*u
					 - 1.0/10.0*u*u*u*u*u);
			b = dih*dih*dih*(4.0/3.0 - 6.0/5.0*u*u
                                          + 1.0/2.0*u*u*u);
		}
		else {
			dir = 1.0/r1;
			a = -1.0/15.0*dir + dih*(8.0/5.0 - 4.0/3.0*u*u +
                            u*u*u - 3.0/10.0*u*u*u*u + 1.0/30.0*u*u*u*u*u);
			b = -1.0/15.0*dir*dir*dir +
                                dih*dih*dih*(8.0/3.0 - 3.0*u +
                                6.0/5.0*u*u - 1.0/6.0*u*u*u);
		}
	  }
	  else {
		a = 1.0/r1;
		b = a*a*a;
	  }
     
          pot[threadIdx.x] -= source_cores[thread].mass * a;

          acc[thread].x += r.x*b*source_cores[thread].mass;
          acc[thread].y += r.y*b*source_cores[thread].mass;
          acc[thread].z += r.z*b*source_cores[thread].mass;
        }
      }
      else{
        if(thread == 0){
          // load shared_particle_core and use
          shared_target_core = particleCores[bucketStart+particle];
        }
        // use shared_target_core
        r.x = (((oid >> 22) & 0x7)-3)*fperiod +
                source_cores[thread].position.x -
                shared_target_core.position.x;

        r.y = (((oid >> 25) & 0x7)-3)*fperiod +
                source_cores[thread].position.y -
                shared_target_core.position.y;

        r.z = (((oid >> 28) & 0x7)-3)*fperiod +
                source_cores[thread].position.z -
                shared_target_core.position.z;

        rsq = r.x*r.x + r.y*r.y + r.z*r.z;
        twoh = source_cores[thread].soft + shared_target_core.soft;
        if(rsq != 0){
          //SPLINE(rsq, twoh, a, b);
          //SPLINE(r2, twoh, a, b);
          //expanded below:
	  cudatype r1, u,dih,dir;
	  r1 = sqrt(rsq);
	  if (r1 < (twoh)) {
		dih = 2.0/(twoh);
		u = r1*dih;
		if (u < 1.0) {
			a = dih*(7.0/5.0 - 2.0/3.0*u*u + 3.0/10.0*u*u*u*u
					 - 1.0/10.0*u*u*u*u*u);
			b = dih*dih*dih*(4.0/3.0 - 6.0/5.0*u*u
                                          + 1.0/2.0*u*u*u);
		}
		else {
			dir = 1.0/r1;
			a = -1.0/15.0*dir + dih*(8.0/5.0 - 4.0/3.0*u*u +
                            u*u*u - 3.0/10.0*u*u*u*u + 1.0/30.0*u*u*u*u*u);
			b = -1.0/15.0*dir*dir*dir +
                                dih*dih*dih*(8.0/3.0 - 3.0*u +
                                6.0/5.0*u*u - 1.0/6.0*u*u*u);
		}
	  }
	  else {
		a = 1.0/r1;
		b = a*a*a;
	  }
     
          pot[threadIdx.x] -= source_cores[thread].mass * a;

          acc[thread].x += r.x*b*source_cores[thread].mass;
          acc[thread].y += r.y*b*source_cores[thread].mass;
          acc[thread].z += r.z*b*source_cores[thread].mass;
        }
          
      }// end else (target >= PART_CACHE_SIZE)
      
      __syncthreads();
      // all threads have computed their portion of the forces
      // time to add forces up
      
      cudatype sum = 0.0;
      if(thread == 0){
        for(int i = 0; i < THREADS_PER_BLOCK; i++){
          sum += acc[i].x;
        }
        particleVars[bucketStart+particle].a.x += sum;
        
        sum = 0;
        for(int i = 0; i < THREADS_PER_BLOCK; i++){
          sum += acc[i].y;
        }
        particleVars[bucketStart+particle].a.y += sum;

        sum = 0;
        for(int i = 0; i < THREADS_PER_BLOCK; i++){
          sum += acc[i].z;
        }
        particleVars[bucketStart+particle].a.z += sum;
        
        sum = 0;
        for(int i = 0; i < THREADS_PER_BLOCK; i++){
          sum += pot[i];
        }
        particleVars[bucketStart+particle].potential += sum;
      }
    }// end for each particle
  }// end for each thread (node)
}
