#include <stdio.h>
#include <thrust/binary_search.h>
#include <thrust/device_vector.h>
#include <thrust/functional.h>
#include <thrust/random.h>
#include <thrust/sort.h>
#include <thrust/transform_reduce.h>

namespace BucketMultiselect{
  using namespace std;

#define MAX_THREADS_PER_BLOCK 1024
#define CUTOFF_POINT 200000 
#define NUM_PIVOTS 17

#define CUDA_CALL(x) do { if((x) != cudaSuccess) {      \
      printf("Error at %s:%d\n",__FILE__,__LINE__);     \
      return EXIT_FAILURE;}} while(0)

  cudaEvent_t start, stop;
  float time;

  void timing(int selection, int ind){
    if(selection==0) {
      //****//
      cudaEventCreate(&start);
      cudaEventCreate(&stop);
      cudaEventRecord(start,0);
      //****//
    }
    else {
      //****//
      cudaThreadSynchronize();
      cudaEventRecord(stop,0);
      cudaEventSynchronize(stop);
      cudaEventElapsedTime(&time, start, stop);
      cudaEventDestroy(start);
      cudaEventDestroy(stop);
      printf("Time %d: %lf \n", ind, time);
      //****//
    }
  }

  template<typename T>
  void cleanup(uint *h_c, T* d_k, int *etb, uint *bc){
    free(h_c);
    cudaFree(d_k);
    cudaFree(etb);
    cudaFree(bc);
  }

  //This function initializes a vector to all zeros on the host (CPU)
  void setToAllZero(uint* deviceVector, int length){
    cudaMemset(deviceVector, 0, length * sizeof(uint));
  }

  //copy elements in the kth bucket to a new array
  template <typename T>
  __global__ void copyElement(T* d_vector, int length, uint* elementToBucket, uint * buckets, const int numBuckets, T* newArray, uint* counter, uint offset, uint * d_bucketCount, int numTotalBuckets){
    int idx = blockIdx.x * blockDim.x + threadIdx.x;

    /*
    extern __shared__ uint sharedBucketCounts[];
    
    for(int i=0; i < 4; i++) 
        sharedBucketCounts[1024 * i + threadIdx.x] = d_bucketCount[blockIdx.x * numTotalBuckets + 1024 * i + threadIdx.x];
    /*
    extern __shared__ uint sharedBuckets[];
    if (threadIdx.x <numBuckets)
      sharedBuckets[threadIdx.x]=buckets[threadIdx.x];
    */
    syncthreads();

    int minBucketIndex;
    int maxBucketIndex; 
    int midBucketIndex;
    uint temp;

    if(idx < length) {
      for(int i=idx; i<length; i+=offset) {
        temp = elementToBucket[i];
        minBucketIndex = 0;
        maxBucketIndex = numBuckets-1;

        //copy elements in the kth buckets to the new array
        for(int j = 1; j < numBuckets; j*=2) {  
          //while (maxBucketIndex >= minBucketIndex) {  
          midBucketIndex = (maxBucketIndex + minBucketIndex) / 2;
          if (temp > buckets[midBucketIndex])
            minBucketIndex=midBucketIndex+1;
          else
            maxBucketIndex=midBucketIndex;
        }

        if (buckets[minBucketIndex] == temp) {
          newArray[atomicDec(d_bucketCount + blockIdx.x * numTotalBuckets + temp, length)] = d_vector[i];
          //[atomicDec(sharedBucketCounts + temp, length)] = d_vector[i];
          //newArray[--sharedBucketCounts[temp]] = d_vector[i];
      }
        
      }
    }

  }

  //this function finds the bin containing the kth element we are looking for (works on the host)
  inline int findKBuckets(uint * d_bucketCount, uint * h_bucketCount, int numBuckets, uint * kVals, int kCount, uint * sums, uint * kthBuckets, int numBlocks){
    int sumsRowIndex= numBuckets * (numBlocks-1);
    // timing(0, 1);
    for(int j=0; j<numBuckets; j++)
      CUDA_CALL(cudaMemcpy(h_bucketCount + j, d_bucketCount + sumsRowIndex + j, sizeof(uint), cudaMemcpyDeviceToHost));
    //timing(1, 1);


    int kBucket = 0;
    int k;
    int sum = h_bucketCount[0];

    for(int i = 0; i < kCount; i++) {
      k = kVals[i];
      while ((sum < k) & (kBucket < numBuckets - 1)) {
        kBucket++;
        sum += h_bucketCount[kBucket];
      }
      kthBuckets[i] = kBucket;
      sums[i] = sum - h_bucketCount[kBucket];
    }

    return 0;
  }

  __global__ void sumCounts(uint * d_bucketCount, const int numBuckets, const int numBlocks) {
    int index = blockIdx.x * blockDim.x + threadIdx.x;

    for(int j=1; j<numBlocks; j++) 
      d_bucketCount[index + numBuckets*j] += d_bucketCount[index + numBuckets*(j-1)];
    
  }

  __global__ void reindexCounts(uint * d_bucketCount, const int numBuckets, const int numBlocks, uint * d_reindexCounter, uint * d_markedBuckets) {
    int index = d_markedBuckets[threadIdx.x];
    int add = d_reindexCounter[threadIdx.x];

    //printf("indexed %d: %u\n", index, d_bucketCount[index]);
    for(int j=0; j<numBlocks; j++) 
      d_bucketCount[index + numBuckets*j] += (uint) add;
    
    //printf("reindexed %d: %u\n", index, d_bucketCount[index]);

    
  }

  
  /************************* BEGIN FUNCTIONS FOR RANDOMIZEDBUCKETSELECT ************************/
  /************************* BEGIN FUNCTIONS FOR RANDOMIZEDBUCKETSELECT ************************/
  /************************* BEGIN FUNCTIONS FOR RANDOMIZEDBUCKETSELECT ************************/
 
  __host__ __device__
  unsigned int hash(unsigned int a)
  {
    a = (a+0x7ed55d16) + (a<<12);
    a = (a^0xc761c23c) ^ (a>>19);
    a = (a+0x165667b1) + (a<<5);
    a = (a+0xd3a2646c) ^ (a<<9);
    a = (a+0xfd7046c5) + (a<<3);
    a = (a^0xb55a4f09) ^ (a>>16);
    return a;
  }

  struct RandomNumberFunctor :
    public thrust::unary_function<unsigned int, float>
  {
    unsigned int mainSeed;

    RandomNumberFunctor(unsigned int _mainSeed) :
      mainSeed(_mainSeed) {}
  
    __host__ __device__
    float operator()(unsigned int threadIdx)
    {
      unsigned int seed = hash(threadIdx) * mainSeed;

      thrust::default_random_engine rng(seed);
      rng.discard(threadIdx);
      thrust::uniform_real_distribution<float> u(0,1);

      return u(rng);
    }
  };

  template <typename T>
  void createRandomVector(T * d_vec, int size) {
    timeval t1;
    uint seed;

    gettimeofday(&t1, NULL);
    seed = t1.tv_usec * t1.tv_sec;
  
    thrust::device_ptr<T> d_ptr(d_vec);
    thrust::transform(thrust::counting_iterator<uint>(0),thrust::counting_iterator<uint>(size),
                      d_ptr, RandomNumberFunctor(seed));
  }

  template <typename T>
  __global__ void enlargeIndexAndGetElements (T * in, T * list, int size) {
    *(in + blockIdx.x*blockDim.x + threadIdx.x) = *(list + ((int) (*(in + blockIdx.x * blockDim.x + threadIdx.x) * size)));
  }


  __global__ void enlargeIndexAndGetElements (float * in, uint * out, uint * list, int size) {
    *(out + blockIdx.x * blockDim.x + threadIdx.x) = (uint) *(list + ((int) (*(in + blockIdx.x * blockDim.x + threadIdx.x) * size)));
  }

  template <typename T>
  void generatePivots (uint * pivots, double * slopes, uint * d_list, int sizeOfVector, int numPivots, int sizeOfSample, int totalSmallBuckets, uint min, uint max) {
  
    float * d_randomFloats;
    uint * d_randomInts;
    int endOffset = 22;
    int pivotOffset = (sizeOfSample - endOffset * 2) / (numPivots - 3);
    int numSmallBuckets = totalSmallBuckets / (numPivots - 1);

    cudaMalloc ((void **) &d_randomFloats, sizeof (float) * sizeOfSample);
  
    d_randomInts = (uint *) d_randomFloats;

    createRandomVector (d_randomFloats, sizeOfSample);

    // converts randoms floats into elements from necessary indices
    enlargeIndexAndGetElements<<<(sizeOfSample/MAX_THREADS_PER_BLOCK), MAX_THREADS_PER_BLOCK>>>(d_randomFloats, d_randomInts, d_list, sizeOfVector);

    pivots[0] = min;
    pivots[numPivots-1] = max;

    thrust::device_ptr<T>randoms_ptr(d_randomInts);
    thrust::sort(randoms_ptr, randoms_ptr + sizeOfSample);

    cudaThreadSynchronize();

    // set the pivots which are next to the min and max pivots using the random element endOffset away from the ends
    cudaMemcpy (pivots + 1, d_randomInts + endOffset - 1, sizeof (uint), cudaMemcpyDeviceToHost);
    cudaMemcpy (pivots + numPivots - 2, d_randomInts + sizeOfSample - endOffset - 1, sizeof (uint), cudaMemcpyDeviceToHost);
    slopes[0] = numSmallBuckets / (double) (pivots[1] - pivots[0]);

    for (int i = 2; i < numPivots - 2; i++) {
      cudaMemcpy (pivots + i, d_randomInts + pivotOffset * (i - 1) + endOffset - 1, sizeof (uint), cudaMemcpyDeviceToHost);
      slopes[i-1] = numSmallBuckets / (double) (pivots[i] - pivots[i-1]);
    }

    slopes[numPivots-3] = numSmallBuckets / (double) (pivots[numPivots-2] - pivots[numPivots-3]);
    slopes[numPivots-2] = numSmallBuckets / (double) (pivots[numPivots-1] - pivots[numPivots-2]);
  
    //    for (int i = 0; i < numPivots - 2; i++)
    //  printf("slopes = %lf\n", slopes[i]);

    cudaFree(d_randomInts);
  }
  
  template <typename T>
  void generatePivots (T * pivots, double * slopes, T * d_list, int sizeOfVector, int numPivots, int sizeOfSample, int totalSmallBuckets, T min, T max) {
      T * d_randoms;
      int endOffset = 22;
      int pivotOffset = (sizeOfSample - endOffset * 2) / (numPivots - 3);
      int numSmallBuckets = totalSmallBuckets / (numPivots - 1);

      cudaMalloc ((void **) &d_randoms, sizeof (T) * sizeOfSample);
  
      createRandomVector (d_randoms, sizeOfSample);

      // converts randoms floats into elements from necessary indices
      enlargeIndexAndGetElements<<<(sizeOfSample/MAX_THREADS_PER_BLOCK), MAX_THREADS_PER_BLOCK>>>(d_randoms, d_list, sizeOfVector);

      pivots[0] = min;
      pivots[numPivots-1] = max;

      thrust::device_ptr<T>randoms_ptr(d_randoms);
      thrust::sort(randoms_ptr, randoms_ptr + sizeOfSample);

      cudaThreadSynchronize();

      // set the pivots which are endOffset away from the min and max pivots
      cudaMemcpy (pivots + 1, d_randoms + endOffset - 1, sizeof (T), cudaMemcpyDeviceToHost);
      cudaMemcpy (pivots + numPivots - 2, d_randoms + sizeOfSample - endOffset - 1, sizeof (T), cudaMemcpyDeviceToHost);
      slopes[0] = numSmallBuckets / (double) (pivots[1] - pivots[0]);

      for (int i = 2; i < numPivots - 2; i++) {
        cudaMemcpy (pivots + i, d_randoms + pivotOffset * (i - 1) + endOffset - 1, sizeof (T), cudaMemcpyDeviceToHost);
        slopes[i-1] = numSmallBuckets / (double) (pivots[i] - pivots[i-1]);
      }

      slopes[numPivots-3] = numSmallBuckets / (double) (pivots[numPivots-2] - pivots[numPivots-3]);
      slopes[numPivots-2] = numSmallBuckets / (double) (pivots[numPivots-1] - pivots[numPivots-2]);
  
      // for (int i = 0; i < numPivots; i++)
      //  printf("pivots = %lf\n", pivots[i]);

      cudaFree(d_randoms);
  }
  
  //this function assigns elements to buckets based off of a randomized sampling of the elements in the vector
  template <typename T>
  __global__ void assignSmartBucket(T * d_vector, int length, int numBuckets, double * slopes, T * pivots, int numPivots, uint* elementToBucket, uint* bucketCount, int offset){
  
    int index = blockDim.x * blockIdx.x + threadIdx.x;
    int bucketIndex;
    int threadIndex = threadIdx.x;  
    
    //variables in shared memory for fast access
    __shared__ int sharedNumSmallBuckets;
    sharedNumSmallBuckets = numBuckets / (numPivots-1);

    extern __shared__ uint sharedBuckets[];
    __shared__ double sharedSlopes[NUM_PIVOTS-1];
    __shared__ T sharedPivots[NUM_PIVOTS];
  
    //reading bucket counts into shared memory where increments will be performed
    for (int i = 0; i < (numBuckets / MAX_THREADS_PER_BLOCK); i++) 
      if (threadIndex < numBuckets) 
        sharedBuckets[i * MAX_THREADS_PER_BLOCK + threadIndex] = 0;

    if(threadIndex < numPivots) {
      sharedPivots[threadIndex] = pivots[threadIndex];
      if(threadIndex < numPivots - 1)
        sharedSlopes[threadIndex] = slopes[threadIndex];
    }
    syncthreads();

    //assigning elements to buckets and incrementing the bucket counts
    if(index < length) {
      int i;

      for(i = index; i < length; i += offset) {
        T num = d_vector[i];
        int minPivotIndex = 0;
        int maxPivotIndex = numPivots-1;
        int midPivotIndex;

        // find the index of the pivot that is the greatest s.t. lower than or equal to num using binary search
        //while (maxPivotIndex > minPivotIndex+1) {
        for(int j = 1; j < numPivots - 1; j*=2) {
          midPivotIndex = (maxPivotIndex + minPivotIndex) / 2;
          if (num >= sharedPivots[midPivotIndex])
            minPivotIndex = midPivotIndex;
          else
            maxPivotIndex = midPivotIndex;
        }

        bucketIndex = (minPivotIndex * sharedNumSmallBuckets) + (int) ((num - sharedPivots[minPivotIndex]) * sharedSlopes[minPivotIndex]);
        elementToBucket[i] = bucketIndex;
        // hashmap implementation set[bucketindex]=add.i;
        //bucketCount[blockIdx.x * numBuckets + bucketIndex]++;
        atomicInc(sharedBuckets + bucketIndex, length);
      }
    }
    
    syncthreads();

    //reading bucket counts from shared memory back to global memory
    for (int i = 0; i < (numBuckets / MAX_THREADS_PER_BLOCK); i++) 
      if (threadIndex < numBuckets) 
        atomicAdd(bucketCount + blockIdx.x * numBuckets + i * MAX_THREADS_PER_BLOCK + threadIndex, sharedBuckets[i * MAX_THREADS_PER_BLOCK + threadIndex]);
    
  }

  /* this function finds the kth-largest element from the input array */
  template <typename T>
  T phaseOneR(T* d_vector, int length, uint * kList, int kListCount, T * output, int blocks, int threads, int pass = 0){    
    /// ***********************************************************
    /// ****STEP 1: Find Min and Max of the whole vector
    /// ****We don't need to go through the rest of the algorithm if its flat
    /// ***********************************************************

    //timing(0, 1);
    //find max and min with thrust
    T maximum, minimum;

    thrust::device_ptr<T>dev_ptr(d_vector);
    thrust::pair<thrust::device_ptr<T>, thrust::device_ptr<T> > result = thrust::minmax_element(dev_ptr, dev_ptr + length);

    minimum = *result.first;
    maximum = *result.second;

    //if the max and the min are the same, then we are done
    if(maximum == minimum) {
      for (int i=0; i<kListCount; i++) 
        output[i] = minimum;
      
      return 0;
    }

    /*
    //if we want the max or min just return it
    if(K == 1){
    return minimum;
    }
    if(K == length){
    return maximum;
    }	
    */	

    //timing(1, 1);
    /// ***********************************************************
    /// ****STEP 2: Declare variables and allocate memory
    /// **** Declare Variables
    /// ***********************************************************

    //timing(0, 2);
    //declaring variables for kernel launches
    int threadsPerBlock = threads;
    int numBlocks = blocks;
    int numBuckets = 4096;
    int offset = blocks * threads;

    // variables for the randomized selection
    int numPivots = NUM_PIVOTS;
    int sampleSize = MAX_THREADS_PER_BLOCK;

    // pivot vars
    double slopes[numPivots - 1];
    double * d_slopes;
    T pivots[numPivots];
    T * d_pivots;

    //Allocate memory to store bucket assignments
    size_t size = length * sizeof(uint);
    uint * d_elementToBucket; //array showing what bucket every element is in
    CUDA_CALL(cudaMalloc(&d_elementToBucket, size));

    //Allocate memory to store bucket counts
    size_t totalBucketSize = numBlocks * numBuckets * sizeof(uint);
    uint h_bucketCount[numBuckets]; //array showing the number of elements in each bucket
    uint * d_bucketCount; 
    CUDA_CALL(cudaMalloc(&d_bucketCount, totalBucketSize));
    setToAllZero(d_bucketCount, numBlocks * numBuckets);

    // array of kth buckets
    int numMarkedBuckets;
    uint * d_kList; 
    uint kthBuckets[kListCount]; 
    uint kthBucketScanner[kListCount]; 
    uint kIndices[kListCount];
    uint * d_kIndices;
    uint markedBuckets[kListCount];
    uint * d_markedBuckets; 
    uint reindexCounter[kListCount];  
    uint * d_reindexCounter;  
    uint * d_markedBucketIndexCounter;  
    CUDA_CALL(cudaMalloc(&d_kList, kListCount * sizeof(uint)));
    CUDA_CALL(cudaMalloc(&d_kIndices, kListCount * sizeof (uint)));
    timing(0, 1);
    for (int i=0; i<kListCount; i++) {
      kthBucketScanner[i] = 0;
      kIndices[i] = i;
    }

    // variable to store the end result
    int newInputLength;
    T* newInput;
    //timing(1, 2);

    /// ***********************************************************
    /// ****STEP 3: Sort the klist
    /// and keep the old index
    /// ***********************************************************

    //timing(0, 3);
    CUDA_CALL(cudaMemcpy(d_kIndices, kIndices, kListCount * sizeof (uint), cudaMemcpyHostToDevice));
    CUDA_CALL(cudaMemcpy(d_kList, kList, kListCount * sizeof (uint), cudaMemcpyHostToDevice)); 

    // sort the given indices
    thrust::device_ptr<uint>kList_ptr(d_kList);
    thrust::device_ptr<uint>kIndices_ptr(d_kIndices);
    thrust::sort_by_key(kList_ptr, kList_ptr + kListCount, kIndices_ptr);

    CUDA_CALL(cudaMemcpy(kIndices, d_kIndices, kListCount * sizeof (uint), cudaMemcpyDeviceToHost));
    CUDA_CALL(cudaMemcpy(kList, d_kList, kListCount * sizeof (uint), cudaMemcpyDeviceToHost)); 

    //timing(1, 3);
    /// ***********************************************************
    /// ****STEP 4: Generate Pivots and Slopes
    /// Declare slopes and pivots
    /// ***********************************************************
    //timing(0, 4);
    CUDA_CALL(cudaMalloc(&d_slopes, (numPivots - 1) * sizeof(double)));
    CUDA_CALL(cudaMalloc(&d_pivots, numPivots * sizeof(T)));

    //Find bucket sizes using a randomized selection
    generatePivots<T>(pivots, slopes, d_vector, length, numPivots, sampleSize, numBuckets, minimum, maximum);
    
    CUDA_CALL(cudaMemcpy(d_slopes, slopes, (numPivots - 1) * sizeof(double), cudaMemcpyHostToDevice));  
     CUDA_CALL(cudaMemcpy(d_pivots, pivots, numPivots * sizeof(T), cudaMemcpyHostToDevice));
    //timing(1, 4);

    /// ***********************************************************
    /// ****STEP 5: Assign elements to buckets
    /// 
    /// ***********************************************************

    timing(0, 5);
    //Distribute elements into their respective buckets
    assignSmartBucket<<<numBlocks, threadsPerBlock, numBuckets * sizeof(uint)>>>(d_vector, length, numBuckets, d_slopes, d_pivots, numPivots, d_elementToBucket, d_bucketCount, offset);
    timing(1, 5);
    timing(0, 6);
    sumCounts<<<numBuckets/threadsPerBlock, threadsPerBlock>>>(d_bucketCount, numBuckets, numBlocks);

    /// ***********************************************************
    /// ****STEP 6: Find the kth buckets
    /// and their respective update indices
    /// ***********************************************************
    //timing(0, 6);
    findKBuckets(d_bucketCount, h_bucketCount, numBuckets, kList, kListCount, kthBucketScanner, kthBuckets, numBlocks);
    //timing(1, 6);

    //timing(0, 7);
    //we must update K since we have reduced the problem size to elements in the kth bucket
    // get the index of the first element
    // add the number of elements    
    markedBuckets[0] = kthBuckets[0];
    reindexCounter[0] = 0;
    numMarkedBuckets = 1;
    kList[0] -= kthBucketScanner[0];

    for (int i = 1; i < kListCount; i++) {
      if (kthBuckets[i] != kthBuckets[i-1]) {
        markedBuckets[numMarkedBuckets] = kthBuckets[i];
        reindexCounter[numMarkedBuckets] = reindexCounter[numMarkedBuckets-1] + h_bucketCount[kthBuckets[i-1]];
        numMarkedBuckets++;
      }
      kList[i] = reindexCounter[numMarkedBuckets-1] + kList[i] - kthBucketScanner[i];
    }

    //store the length of the newly copied elements    
    newInputLength = reindexCounter[numMarkedBuckets-1] + h_bucketCount[kthBuckets[kListCount - 1]];

    //timing(1, 7);
    printf("randomselect total kbucket_count = %d\n", newInputLength);

    /*
    for (int i = 0; i < numMarkedBuckets; i++) 
      printf("reindex %d = %u\n", i, reindexCounter[i]);
    */
    /// ***********************************************************
    CUDA_CALL(cudaMalloc(&d_reindexCounter, numMarkedBuckets * sizeof(uint)));
    CUDA_CALL(cudaMalloc(&d_markedBuckets, numMarkedBuckets * sizeof(uint)));

    CUDA_CALL(cudaMemcpy(d_reindexCounter, reindexCounter, numMarkedBuckets * sizeof(uint), cudaMemcpyHostToDevice));
    CUDA_CALL(cudaMemcpy(d_markedBuckets, markedBuckets, numMarkedBuckets * sizeof(uint), cudaMemcpyHostToDevice));

    reindexCounts<<<1, numMarkedBuckets>>>(d_bucketCount, numBuckets, numBlocks, d_reindexCounter, d_markedBuckets);

    /// ***********************************************************

    /// ***********************************************************
    /// ****STEP 7: Copy the kth buckets
    /// only marked ones
    /// ***********************************************************

    //timing(0, 8);
    // allocate memories
    CUDA_CALL(cudaMalloc(&newInput, newInputLength * sizeof(T)));
    //CUDA_CALL(cudaMalloc(&d_markedBuckets, numMarkedBuckets * sizeof(uint)));
    CUDA_CALL(cudaMalloc(&d_markedBucketIndexCounter, sizeof(uint)));

    //copy marked bucket stuff into device
    //CUDA_CALL(cudaMemcpy(d_markedBuckets, markedBuckets, numMarkedBuckets * sizeof(uint), cudaMemcpyHostToDevice));
    setToAllZero(d_markedBucketIndexCounter, 1);
    //timing(1, 8);
    timing(1, 6);
    timing(0, 9);

    //copyElement<<<numBlocks, threadsPerBlock, numMarkedBuckets * sizeof(uint)>>>(d_vector, length, d_elementToBucket, d_markedBuckets, numMarkedBuckets, newInput, d_markedBucketIndexCounter, offset, h_bucketCount);
    copyElement<<<numBlocks, threadsPerBlock, numBuckets * sizeof(uint)>>>(d_vector, length, d_elementToBucket, d_markedBuckets, numMarkedBuckets, newInput, d_markedBucketIndexCounter, offset, d_bucketCount, numBuckets);
    timing(1, 9);

    /// ***********************************************************
    /// ****STEP 8: Sort
    /// and finito
    /// ***********************************************************

    //timing(0, 10);
    // sort the vector
    thrust::device_ptr<T>newInput_ptr(newInput);
    thrust::sort(newInput_ptr, newInput_ptr + newInputLength);
    
    //printf("newInputLength = %d\n", newInputLength);
    for (int i = 0; i < kListCount; i++) {
      //printf("kList[%d] = %u\n", i, kList[i]);
      CUDA_CALL(cudaMemcpy(output + kIndices[i], newInput + kList[i] - 1, sizeof (T), cudaMemcpyDeviceToHost));
    }
    //timing(1, 10);
    
    /*
      } else
      kthValue = phaseTwo(newInput,newInputLength, K, blocks, threads,maximum, minimum);
      
      /*
      minimum = max(minimum, minimum + kthBucket/slope);
      maximum = min(maximum, minimum + 1/slope);
      kthValue = phaseTwo(newInput,newInputLength, K, blocks, threads,maximum, minimum);
   
      }*/

  //free all used memory
  cudaFree(d_elementToBucket);  
  cudaFree(d_bucketCount); 
  cudaFree(newInput); 
  cudaFree(d_slopes); 
  cudaFree(d_kIndices); 
  cudaFree(d_kList); 
  cudaFree(d_reindexCounter);  
  cudaFree(d_markedBuckets); 
  cudaFree(d_markedBucketIndexCounter); 
  cudaFree(d_pivots);

  return 0;

  }

  template <typename T>
  T bucketMultiselectWrapper (T * d_vector, int length, uint * kList_ori, int kListCount, T * outputs, int blocks, int threads) { 
    uint kList[kListCount];
    for(int i=0; i<kListCount ; i++)
      kList[i] = length - kList_ori[i] + 1;
    /*
    printf("start here\n");
    printf("k-length: %d\n", length);
    for(int i=0; i<kListCount ; i++)
      printf("k-%d: %d\n", i, kList[i]);
    */

    //  if(length <= CUTOFF_POINT) 
    //  phaseTwo(d_vector, length, kList, kListCount, outputs, blocks, threads);
    //  else 
    phaseOneR(d_vector, length, kList, kListCount, outputs, blocks, threads);
    // void phaseOneR(T* d_vector, int length, uint * kList, uint kListCount, T * outputs, int blocks, int threads, int pass = 0){

    return 0;
  }

}

