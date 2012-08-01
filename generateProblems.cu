/* Copyright 2011 Russel Steinbach, Jeffrey Blanchard, Bradley Gordon,
 *   and Toluwaloju Alabi
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *     
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <cuda.h>
#include <curand.h>
#define CUDART_PI_F 3.141592654f

///////////////////////////////////////////////////////////////////
////           FUNCTIONS TO GENERATE UINTS
///////////////////////////////////////////////////////////////////
typedef void (*ptrToUintGeneratingFunction)(uint*, uint, curandGenerator_t);

void generateUniformUnsignedIntegers(uint *h_vec, uint numElements, curandGenerator_t generator){
  uint * d_generated;
  cudaMalloc(&d_generated, numElements * sizeof(uint));
  curandGenerate(generator, d_generated,numElements);
  cudaMemcpy(h_vec, d_generated, numElements * sizeof(uint), cudaMemcpyDeviceToHost);
  cudaFree(d_generated);
}


void generateSortedArrayUints(uint* input, uint length, curandGenerator_t gen)
{
  uint * d_generated;
  cudaMalloc(&d_generated, length * sizeof(uint));
  curandGenerate(gen, d_generated,length);
  thrust::device_ptr<uint>d_ptr(d_generated);
  thrust::sort(d_ptr, d_ptr+length);
  cudaMemcpy(input, d_generated, length * sizeof(uint), cudaMemcpyDeviceToHost);

  cudaFree(d_generated);
}

void generateUniformZeroToFourUints (uint* input, uint length, curandGenerator_t gen) {

  for (uint i = 0; i < length; i++)
    input[i] = i % 4;

}

#define NUMBEROFUINTDISTRIBUTIONS 3
ptrToUintGeneratingFunction arrayOfUintGenerators[NUMBEROFUINTDISTRIBUTIONS] = {&generateUniformUnsignedIntegers,&generateSortedArrayUints,&generateUniformZeroToFourUints};
char* namesOfUintGeneratingFunctions[NUMBEROFUINTDISTRIBUTIONS]={"UNIFORM UNSIGNED INTEGERS","SORTED UINTS","UNIFORM 0-4"};

///////////////////////////////////////////////////////////////////
////           FUNCTIONS TO GENERATE FLOATS
///////////////////////////////////////////////////////////////////
typedef void (*ptrToFloatGeneratingFunction)(float*, uint, curandGenerator_t);

void generateUniformFloats(float *h_vec, uint numElements, curandGenerator_t generator){
  float * d_generated;
  cudaMalloc(&d_generated, numElements * sizeof(float));
  curandGenerateUniform(generator, d_generated,numElements);
  cudaMemcpy(h_vec, d_generated, numElements * sizeof(float), cudaMemcpyDeviceToHost);
  cudaFree(d_generated);
}

void generateNormalFloats(float* h_vec, uint numElements, curandGenerator_t generator){
  float *d_generated;
  cudaMalloc(&d_generated, numElements * sizeof(float));
  curandGenerateNormal(generator, d_generated, numElements,0,1);
  cudaMemcpy(h_vec, d_generated, numElements * sizeof(float), cudaMemcpyDeviceToHost);
  cudaFree(d_generated);
}
__global__ void setAllToValue(float* input, int length, float value, int offset)
{
  int idx = blockDim.x * blockIdx.x + threadIdx.x;
  if(idx < length){
    int i;
    for(i=idx; i<length; i+=offset){
      input[i] = value;
    }
  }
}

__global__ void createVector(float* input, int length, int firstVal, int numFirstVal, int secondVal, int numSecondVal, int offset){
  int idx = blockDim.x * blockIdx.x + threadIdx.x;

  if(idx < length){
    int i;
    for(i=idx; i< numFirstVal; i+=offset){
      input[i] = firstVal;
    }
    syncthreads();

    for(i=idx; i< (numFirstVal + numSecondVal); i+=offset){
      if(i >= numFirstVal){
        input[i] = secondVal;
      }
    }
  }
}


__global__ void scatter(float* input, int length, int offset){
  int idx = blockDim.x * blockIdx.x + threadIdx.x;

  if( (idx < length) && ((idx % 2) == 0) ){
    int i, j;
    int lastEvenIndex = (length-1) - ( (length-1) % 2);
    float temp;

    for(i=idx; i< (length/2); i+=offset){
      //if i is even
      if( (i % 2) == 0)
        j = lastEvenIndex - i;

      //switch i and j
      temp = input[i];
      input[i] = input[j];
      input[j] = temp;
    }
  }
}

//takes in a device input vector
void generateOnesTwosNoisyFloats(float* input, int length, int firstVal, int firstPercent, int secondVal, int secondPercent)
{
  float* devVec;
  cudaMalloc(&devVec, sizeof(float) * length);

  int numFirstVal = (length * firstPercent) / 100;
  int numSecondVal = length - numFirstVal;

  //get device properties
  cudaDeviceProp deviceProp;
  cudaGetDeviceProperties(&deviceProp, 0);
  int blocks = deviceProp.multiProcessorCount;
  int maxThreads = deviceProp.maxThreadsPerBlock;
  int offset = blocks * maxThreads;

  //create vector of ones and twos
  createVector<<<blocks, maxThreads>>>(devVec, length, firstVal, numFirstVal, secondVal, numSecondVal, offset);

  //shuffle the elements of the vector
  scatter<<<blocks, maxThreads>>>(devVec, length, offset);

  cudaMemcpy(input, devVec, sizeof(float)*length, cudaMemcpyDeviceToHost);
  cudaFree(devVec);
} 

void generateOnesTwosFloats(float* input, uint length, curandGenerator_t gen) 
{
  float* devVec;
  cudaMalloc(&devVec, sizeof(float) * length);

  int numFirstVal = (length * 50) / 100;
  int numSecondVal = length - numFirstVal;

  //get device properties
  cudaDeviceProp deviceProp;
  cudaGetDeviceProperties(&deviceProp, 0);
  int blocks = deviceProp.multiProcessorCount;
  int maxThreads = deviceProp.maxThreadsPerBlock;
  int offset = blocks * maxThreads;

  //create vector of ones and twos
  createVector<<<blocks, maxThreads>>>(devVec, length, 2, numFirstVal, 1, numSecondVal, offset);

  //shuffle the elements of the vector
  scatter<<<blocks, maxThreads>>>(devVec, length, offset);

  cudaMemcpy(input, devVec, sizeof(float)*length, cudaMemcpyDeviceToHost);
  cudaFree(devVec);
}

//sets everything in this vector to 1.0
void generateAllOnesFloats(float* input, uint length, curandGenerator_t gen)
{
  float* devVec;
  cudaMalloc(&devVec, sizeof(float) * length);

  //get device properties
  cudaDeviceProp deviceProp;
  cudaGetDeviceProperties(&deviceProp, 0);
  int blocks = deviceProp.multiProcessorCount;
  int maxThreads = deviceProp.maxThreadsPerBlock;
  int offset = blocks * maxThreads;

  setAllToValue<<<blocks, maxThreads>>>(devVec, length, 1.0, offset);

  cudaMemcpy(input, devVec, sizeof(float)*length, cudaMemcpyDeviceToHost);

  cudaFree(devVec);
}

//add first and second and store it in first
__global__ void vectorAdd(float* first, float* second, int length, int offset){
  int idx = blockDim.x * blockIdx.x + threadIdx.x;
  if(idx < length){
    int i;
    
    for(i=idx; i<length; i+=offset){
      first[i] = first[i] + second[i];
    }
  }
}

//divide first by second and store it in first
__global__ void CauchyTransformFloat(float* vec, int length, int offset) {
  int idx = blockDim.x * blockIdx.x + threadIdx.x;
  if(idx < length){
    int i;

    for(i=idx; i<length; i+=offset){
      if(vec[i] == 1)
        vec[i] = 0.9999;
      if(vec[i] == 0)
        vec[i] = 0.0001;
      
      vec[i] = tanf(CUDART_PI_F*(vec[i] - 0.5));
    }
  }
}

void generateCauchyFloats(float* input, uint length, curandGenerator_t gen){
  float* devInput;

  cudaMalloc(&devInput, sizeof(float)*length);

  //get device properties
  cudaDeviceProp deviceProp;
  cudaGetDeviceProperties(&deviceProp, 0);
  int blocks = deviceProp.multiProcessorCount;
  int maxThreads = deviceProp.maxThreadsPerBlock;
  int offset = blocks * maxThreads;

  curandGenerateUniform(gen, devInput, length);

  CauchyTransformFloat<<<blocks, maxThreads>>>(devInput, length, offset);

  cudaMemcpy(input, devInput, sizeof(float)*length, cudaMemcpyDeviceToHost);

  cudaFree(devInput);
}

void generateNoisyVector(float* input, uint length, curandGenerator_t gen){
  float* devInput;
  cudaMalloc(&devInput, sizeof(float)*length);

 
  curandGenerateNormal(gen, devInput, length, 0.0, 0.01);

  //get device properties
  cudaDeviceProp deviceProp;
  cudaGetDeviceProperties(&deviceProp, 0);
  int blocks = deviceProp.multiProcessorCount;
  int maxThreads = deviceProp.maxThreadsPerBlock;
  int offset = blocks * maxThreads;

  float* hostVec = (float*)malloc(sizeof(float)*length);
  float* devVec;
  cudaMalloc(&devVec, sizeof(float) *length);

  generateOnesTwosNoisyFloats(hostVec, length, 1.0, 20, 0.0, 80);
  cudaMemcpy(devVec, hostVec, sizeof(float)*length, cudaMemcpyHostToDevice);

  vectorAdd<<<blocks, maxThreads>>>(devInput, devVec, length, offset);

  cudaMemcpy(input, devInput, sizeof(float)*length, cudaMemcpyDeviceToHost);

  cudaFree(devInput);
  cudaFree(devVec);
  free(hostVec);
}

struct multiplyByMillion
{
  __host__ __device__
  void operator()(float &key){
    key = key * 1000000;
  }
};

void generateHugeUniformFloats(float* input, uint length, curandGenerator_t gen){
  float* devInput;
  cudaMalloc(&devInput, sizeof(float) * length);

  
  curandGenerateUniform(gen, devInput, length);
  thrust::device_ptr<float> dev_ptr(devInput);
  thrust::for_each( dev_ptr, dev_ptr + length, multiplyByMillion());
  cudaMemcpy(input, devInput, sizeof(float)*length, cudaMemcpyDeviceToHost);

  cudaFree(devInput);
}


void generateNormalFloats100(float* input, uint length, curandGenerator_t gen){
  float* devInput;
  cudaMalloc(&devInput, sizeof(float) * length);
  curandGenerateNormal(gen, devInput, length, 0.0, 100.0);
  cudaMemcpy(input, devInput, sizeof(float)*length, cudaMemcpyDeviceToHost);
  cudaFree(devInput);
}


__global__ void createAbsolute(float* input, int length, int offset){
  int idx = blockDim.x * blockIdx.x + threadIdx.x;

  if(idx < length){
    int i;
    for(i=idx; i< length; i+=offset){
      input[i] = abs(input[i]);
    }
  }
}


void generateHalfNormalFloats(float* input, uint length, curandGenerator_t gen){
  float* devInput;
  cudaMalloc(&devInput, sizeof(float) * length);

  
  curandGenerateNormal(gen, devInput, length, 0.0, 1.0);

  //get device properties
  cudaDeviceProp deviceProp;
  cudaGetDeviceProperties(&deviceProp, 0);
  int blocks = deviceProp.multiProcessorCount;
  int maxThreads = deviceProp.maxThreadsPerBlock;
  int offset = blocks * maxThreads;

  createAbsolute<<<blocks, maxThreads>>>(devInput, length, offset);

  cudaMemcpy(input, devInput, sizeof(float)*length, cudaMemcpyDeviceToHost);

  cudaFree(devInput);
}


struct makeSmallFloat
{
  __host__ __device__
  void operator()(uint &key){
    key = key & 0x80EFFFFF;
  }
};


void generateBucketKillerFloats(float *h_vec, uint numElements, curandGenerator_t generator){
  int i;
  float * d_generated;
  cudaMalloc(&d_generated, numElements * sizeof(float));
  curandGenerateUniform(generator, d_generated,numElements);
  thrust::device_ptr<unsigned int> dev_ptr((uint *)d_generated);
  thrust::for_each( dev_ptr, dev_ptr + numElements, makeSmallFloat());
  thrust::sort(dev_ptr,dev_ptr + numElements);
  cudaMemcpy(h_vec, d_generated, numElements * sizeof(float), cudaMemcpyDeviceToHost);
 
  for(i = -126; i < 127; i++){
    h_vec[i + 126] = pow(2.0,(float)i);
  }
  cudaFree(d_generated);
}

#define NUMBEROFFLOATDISTRIBUTIONS 10
ptrToFloatGeneratingFunction arrayOfFloatGenerators[NUMBEROFFLOATDISTRIBUTIONS] = {&generateUniformFloats, &generateNormalFloats,&generateBucketKillerFloats,
                                                                                   &generateHalfNormalFloats,&generateNormalFloats100, &generateHugeUniformFloats,
                                                                                   &generateNoisyVector,&generateAllOnesFloats,&generateOnesTwosFloats, &generateCauchyFloats};

char* namesOfFloatGeneratingFunctions[NUMBEROFFLOATDISTRIBUTIONS]={"UNIFORM FLOATS","NORMAL FLOATS","KILLER FLOATS",
                                                                   "HALF NORMAL FLOATS","NORMAL FLOATS 100", "HUGE UNIFORM FLOATS",
                                                                   "NOISY FLOATS","ALL ONES FLOATS","ONES TWOS FLOAT", "CAUCHY FLOAT"};


///////////////////////////////////////////////////////////////////
////           FUNCTIONS TO GENERATE DOUBLES
///////////////////////////////////////////////////////////////////

typedef void (*ptrToDoubleGeneratingFunction)(double*, uint, curandGenerator_t);

void generateUniformDoubles(double *h_vec, uint numElements, curandGenerator_t generator){
  double * d_generated;
  cudaMalloc(&d_generated, numElements * sizeof(double));
  curandGenerateUniformDouble(generator, d_generated,numElements);
  cudaMemcpy(h_vec, d_generated, numElements * sizeof(double), cudaMemcpyDeviceToHost);
  cudaFree(d_generated);
}

void generateNormalDoubles(double* h_vec, uint numElements, curandGenerator_t gen){
  double *d_generated;
  cudaMalloc(&d_generated, numElements * sizeof(double));
  curandGenerateNormalDouble(gen, d_generated, numElements,0,1);
  cudaMemcpy(h_vec, d_generated, numElements * sizeof(double), cudaMemcpyDeviceToHost);
  cudaFree(d_generated);
}

struct makeSmallDouble
{
  __host__ __device__
  void operator()(unsigned long long &key){
    key = key & 0x800FFFFFFFFFFFFF;
  }
};

void generateBucketKillerDoubles(double *h_vec, uint numElements, curandGenerator_t generator){
   int i;
   double * d_generated;
   cudaMalloc(&d_generated, numElements * sizeof(double));
   curandGenerateUniformDouble(generator, d_generated,numElements);
   thrust::device_ptr<unsigned long long> dev_ptr((unsigned long long *)d_generated);
   thrust::for_each( dev_ptr, dev_ptr + numElements, makeSmallDouble());
    thrust::sort(dev_ptr,dev_ptr + numElements);
   cudaMemcpy(h_vec, d_generated, numElements * sizeof(double), cudaMemcpyDeviceToHost);
 
   for(i = -1022; i < 1023; i++){
     h_vec[i + 1022] = pow(2.0,(double)i);
   }
   cudaFree(d_generated);
}

#define NUMBEROFDOUBLEDISTRIBUTIONS 3
ptrToDoubleGeneratingFunction arrayOfDoubleGenerators[NUMBEROFDOUBLEDISTRIBUTIONS] = {&generateUniformDoubles,&generateNormalDoubles,
                                                                                      &generateBucketKillerDoubles};
char* namesOfDoubleGeneratingFunctions[NUMBEROFDOUBLEDISTRIBUTIONS]={"UNIFORM DOUBLES","NORMAL DOUBLES", "KILLER DOUBLES"};



template<typename T> void* returnGenFunctions(){
  if(typeid(T) == typeid(uint)){
    return arrayOfUintGenerators;
  }
  else if(typeid(T) == typeid(float)){
    return arrayOfFloatGenerators;
  }
  else{
    return arrayOfDoubleGenerators;
  }
}


template<typename T> char** returnNamesOfGenerators(){
  if(typeid(T) == typeid(uint)){
    return &namesOfUintGeneratingFunctions[0];
  }
  else if(typeid(T) == typeid(float)){
    return &namesOfFloatGeneratingFunctions[0];
  }
  else {
    return &namesOfDoubleGeneratingFunctions[0];
  }
}


void printDistributionOptions(uint type){
  switch(type){
  case 1:
    PrintFunctions::printArray(returnNamesOfGenerators<float>(), NUMBEROFFLOATDISTRIBUTIONS);
    break;
  case 2:
    PrintFunctions::printArray(returnNamesOfGenerators<double>(), NUMBEROFDOUBLEDISTRIBUTIONS);
    break;
  case 3:
    PrintFunctions::printArray(returnNamesOfGenerators<uint>(), NUMBEROFUINTDISTRIBUTIONS);
    break;
  default:
    printf("You entered and invalid option\n");
    break;
  }
}



/********** K DISTRIBUTION GENERATOR FUNCTIONS ************/

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
    thrust::uniform_real_distribution<float> u(0, 1);

    return u(rng);
  }
};

void generateKUniformRandom (uint * kList, uint kListCount, uint vectorSize, curandGenerator_t generator) {
  float * randomFloats = (float *) malloc (kListCount * sizeof (float));
  float * d_randomFloats;

  cudaMalloc (&d_randomFloats, sizeof (float) * kListCount);
  
  timeval t1;
  uint seed;

  gettimeofday(&t1, NULL);
  seed = t1.tv_usec * t1.tv_sec;
  
  thrust::device_ptr<float> d_ptr(d_randomFloats);
  thrust::transform(thrust::counting_iterator<uint>(0),thrust::counting_iterator<uint>(kListCount), d_ptr, RandomNumberFunctor(seed));


  cudaMemcpy (randomFloats, d_randomFloats, kListCount * sizeof (float), cudaMemcpyDeviceToHost);

  for (int i = 0; i < kListCount; i++)
    kList[i] = (uint) (randomFloats[i] * (float) vectorSize);
    
  cudaFree (d_randomFloats);
  free (randomFloats);
}

void generateKUniform (uint * kList, uint kListCount, uint vectorSize, curandGenerator_t generator) {
  kList[0] = 2;
  for (uint i = 1; i < kListCount; i++) 
    kList[i] = (uint) ((i / (float) kListCount) * vectorSize);
}

void generateKNormal (uint * kList, uint kListCount, uint vectorSize, curandGenerator_t generator) {


}


void generateKCluster (uint * kList, uint kListCount, uint vectorSize, curandGenerator_t generator) {



}

#define NUMBEROFKDISTRIBUTIONS 4
typedef void (*ptrToKDistributionGenerator)(uint *, uint, uint, curandGenerator_t);
ptrToKDistributionGenerator arrayOfKDistributionGenerators[NUMBEROFKDISTRIBUTIONS] = {&generateKUniformRandom, &generateKUniform, &generateKNormal, &generateKCluster};
char* namesOfKGenerators[NUMBEROFKDISTRIBUTIONS] = {"Generate Uniform Random Ks", "Generate Uniform Ks", "Generate Normal Random Ks", "Generate Cluster Ks"};
