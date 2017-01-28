/*
 * algoritmo_a.cu
 *
 *  Created on: 18/01/2017
 *      Author: alfonso
 */
#include "distlocrec.h"

void calculaDLRv2(float radio);
void alojaMemoria(void);
void liberaMemoria(void);
void imprimeResultado(float radio);

extern int cantiloc;
extern int cantirec;
extern PLocalidad ploc;
extern PRecurso prec;
extern PDiccionario pdic;

extern int cantixtipo[CANTI_TIPO_REC];

//coordenadas de las localidades
float *hloc_x;
float *hloc_y;
float *hloc_z;

float *dloc_x;
float *dloc_y;
float *dloc_z;

//coordenadas de los recursos

float *hrec_x;
float *hrec_y;
float *hrec_z;
int *hrec_uid;

float *drec_x;
float *drec_y;
float *drec_z;
int *drec_uid;

//valores resultantes del calculo

float *hdist_resultado;
float *ddist_resultado;

int *hidrec_resultado;
int *didrec_resultado;

/**
 *
 */
__global__ void calculadistLRv3(int nlocs, int nrecsR, int ntipo, int offset,
		int tambrec, float* dloc_x, float* dloc_y, float* dloc_z, float* drec_x,
		float* drec_y, float* drec_z, int* drec_uid, float *ddist_resultado,
		int *didrec_resultado) {

	extern __shared__ float s[];
	float* shfrec_x = s;
	float* shfrec_y = (s + tambrec);
	float* shfrec_z = (s + 2 * tambrec);
	int* shirec_uid = (int *) (s + 3 * tambrec);

	unsigned int id = blockIdx.x * blockDim.x + threadIdx.x;

	float dist = 4;
	int idrec = -1;
	float daux;
	unsigned int j;

	if (id < nlocs) {
		float x = *(dloc_x + id);
		float y = *(dloc_y + id);
		float z = *(dloc_z + id);

		for (j = threadIdx.x; j < tambrec; j += blockDim.x) {

			*(shfrec_x + j) = *(drec_x + j);
			*(shfrec_y + j) = *(drec_y + j);
			*(shfrec_z + j) = *(drec_z + j);
			*(shirec_uid + j) = *(drec_uid + j);
		}

		__syncthreads();

		for (int k = 0; k < tambrec; k++) {
			daux = *(shfrec_x + k) * x + *(shfrec_y + k) * y
					+ *(shfrec_z + k) * z;
			daux = acosf(daux);
			if (daux < dist) {
				dist = daux;
				idrec = *(shirec_uid + k);
			}
		}

		__syncthreads();

		*(ddist_resultado + (id * CANTI_TIPO_REC) + ntipo) = dist;
		*(didrec_resultado + (id * CANTI_TIPO_REC) + ntipo) = idrec;

	}

}

/**
 *
 */
__global__ void calculadistLRv3G(int nlocs, int nrecsR, int ntipo, int offset,
		int tambrec, float* dloc_x, float* dloc_y, float* dloc_z, float* drec_x,
		float* drec_y, float* drec_z, int* drec_uid, float *ddist_resultado,
		int *didrec_resultado) {

	extern __shared__ float s[];
	float* shfrec_x = s;
	float* shfrec_y = (s + tambrec);
	float* shfrec_z = (s + 2 * tambrec);
	int* shirec_uid = (int *) (s + 3 * tambrec);

	unsigned int id = blockIdx.x * blockDim.x + threadIdx.x;

	float dist = 4;
	int idrec = -1;
	float daux;
	unsigned int k, j, tambrec_loc = tambrec;
	unsigned int rec_faltantes = nrecsR, avance = 0;

	int vueltas = 0;

	if (id < nlocs) {
		float x = *(dloc_x + id);
		float y = *(dloc_y + id);
		float z = *(dloc_z + id);

		do {
			j = threadIdx.x;
			while (j < tambrec_loc && (j + avance) < nrecsR) {

				*(shfrec_x + j) = *(drec_x + j + avance);
				*(shfrec_y + j) = *(drec_y + j + avance);
				*(shfrec_z + j) = *(drec_z + j + avance);
				*(shirec_uid + j) = *(drec_uid + j + avance);

				j += blockDim.x;
			}

			__syncthreads();

			for (k = 0; k < tambrec_loc; k++) {
				daux = *(shfrec_x + k) * x + *(shfrec_y + k) * y
						+ *(shfrec_z + k) * z;
				daux = acosf(daux);
				if (daux < dist) {
					dist = daux;
					idrec = *(shirec_uid + k);
				}
			}

			avance += tambrec_loc;
			rec_faltantes -= avance;

			if (rec_faltantes < tambrec_loc) {
				tambrec_loc = rec_faltantes;
			}

			__syncthreads();

			vueltas++;
		} while (rec_faltantes > 0 && vueltas < 4);

		*(ddist_resultado + (id * CANTI_TIPO_REC) + ntipo) = dist;
		*(didrec_resultado + (id * CANTI_TIPO_REC) + ntipo) = idrec;

	}

}

__global__ void calculadistLRv3G_vacio(int nlocs, int nrecsR, int ntipo,
		int offset, int tambrec, float* dloc_x, float* dloc_y, float* dloc_z,
		float* drec_x, float* drec_y, float* drec_z, int* drec_uid,
		float *ddist_resultado, int *didrec_resultado) {

	unsigned int id = blockIdx.x * blockDim.x + threadIdx.x;

	*(ddist_resultado + (id * CANTI_TIPO_REC) + ntipo) = 0;
	*(didrec_resultado + (id * CANTI_TIPO_REC) + ntipo) = 0;
}

/**
 *
 */
void calculaDLRv2(float radio) {

	int tema;

	int canti_hilos = 640;
	int canti_bloques = ceil(cantiloc / canti_hilos) + 1;

	const unsigned int tambrec = 3072;

	size_t tamsharedmem;

	alojaMemoria();
	cudaStream_t stream[CANTI_TIPO_REC];

	int offset = 0;

	cudaMemcpy(dloc_x, hloc_x, cantiloc * sizeof(float),
			cudaMemcpyHostToDevice);
	cudaMemcpy(dloc_y, hloc_y, cantiloc * sizeof(float),
			cudaMemcpyHostToDevice);
	cudaMemcpy(dloc_z, hloc_z, cantiloc * sizeof(float),
			cudaMemcpyHostToDevice);

	cudaMemcpy(drec_x, hrec_x, cantirec * sizeof(float),
			cudaMemcpyHostToDevice);
	cudaMemcpy(drec_y, hrec_y, cantirec * sizeof(float),
			cudaMemcpyHostToDevice);
	cudaMemcpy(drec_z, hrec_z, cantirec * sizeof(float),
			cudaMemcpyHostToDevice);
	cudaMemcpy(drec_uid, hrec_uid, cantirec * sizeof(int),
			cudaMemcpyHostToDevice);

	for (tema = 0; tema < CANTI_TIPO_REC; tema++) {

		cudaStreamCreate(&stream[tema]);

		if (cantixtipo[tema] < tambrec) {

			tamsharedmem = sizeof(float) * 4 * cantixtipo[tema];

			printf("Kernel chico: %d => %d\n", tema, cantixtipo[tema]);

			calculadistLRv3<<<canti_bloques, canti_hilos, tamsharedmem,
					stream[tema]>>>(cantiloc, cantixtipo[tema], tema, offset,
					cantixtipo[tema], dloc_x, dloc_y, dloc_z, (drec_x + offset),
					(drec_y + offset), (drec_z + offset), (drec_uid + offset),
					ddist_resultado, didrec_resultado);

		} else {
			tamsharedmem = sizeof(float) * 4 * tambrec;
			printf("Kernel GRANDE: %d => %d\n", tema, cantixtipo[tema]);


			calculadistLRv3G<<<canti_bloques, canti_hilos, tamsharedmem,
					stream[tema]>>>(cantiloc, cantixtipo[tema], tema, offset,
					tambrec, dloc_x, dloc_y, dloc_z, (drec_x + offset),
					(drec_y + offset), (drec_z + offset), (drec_uid + offset),
					ddist_resultado, didrec_resultado);

		}

		offset += cantixtipo[tema];
	}

	for (tema = 0; tema < CANTI_TIPO_REC; tema++) {
		cudaStreamSynchronize(stream[tema]);
	}

	cudaMemcpy(hdist_resultado, ddist_resultado,
			cantiloc * CANTI_TIPO_REC * sizeof(float), cudaMemcpyDeviceToHost);

	cudaMemcpy(hidrec_resultado, didrec_resultado,
			cantiloc * CANTI_TIPO_REC * sizeof(int), cudaMemcpyDeviceToHost);

	imprimeResultado(radio);

	liberaMemoria();
}

/**
 *
 */
void alojaMemoria(void) {
//Localidades
	hloc_x = (float*) malloc(sizeof(float) * cantiloc);
	hloc_y = (float*) malloc(sizeof(float) * cantiloc);
	hloc_z = (float*) malloc(sizeof(float) * cantiloc);

	for (int i = 0; i < cantiloc; i++) {
		Localidad p = *(ploc + i);
		*(hloc_x + i) = p.x;
		*(hloc_y + i) = p.y;
		*(hloc_z + i) = p.z;
	}

	cudaMalloc((void**) &(dloc_x), cantiloc * sizeof(float));
	cudaMalloc((void**) &(dloc_y), cantiloc * sizeof(float));
	cudaMalloc((void**) &(dloc_z), cantiloc * sizeof(float));

//Recursos
	hrec_x = (float*) malloc(sizeof(float) * cantirec);
	hrec_y = (float*) malloc(sizeof(float) * cantirec);
	hrec_z = (float*) malloc(sizeof(float) * cantirec);
	hrec_uid = (int*) malloc(sizeof(float) * cantirec);

	for (int i = 0; i < cantirec; i++) {
		Recurso p = *(prec + i);
		*(hrec_x + i) = p.x;
		*(hrec_y + i) = p.y;
		*(hrec_z + i) = p.z;
		*(hrec_uid + i) = p.uniq_id;
	}

	cudaMalloc((void**) &(drec_x), cantirec * sizeof(float));
	cudaMalloc((void**) &(drec_y), cantirec * sizeof(float));
	cudaMalloc((void**) &(drec_z), cantirec * sizeof(float));
	cudaMalloc((void**) &(drec_uid), cantirec * sizeof(int));

//Resultados
	cudaMallocHost((void **) &(hdist_resultado),
			cantiloc * CANTI_TIPO_REC * sizeof(float));

	cudaMalloc((void**) &(ddist_resultado),
			cantiloc * CANTI_TIPO_REC * sizeof(float));

	cudaMallocHost((void **) &(hidrec_resultado),
			cantiloc * CANTI_TIPO_REC * sizeof(int));

	cudaMalloc((void**) &(didrec_resultado),
			cantiloc * CANTI_TIPO_REC * sizeof(int));

}

/**
 *
 */
void liberaMemoria(void) {

	cudaFree(didrec_resultado);
	cudaFreeHost(hidrec_resultado);

	cudaFree(ddist_resultado);
	cudaFreeHost(hdist_resultado);

	cudaFree(drec_uid);
	cudaFree(drec_z);
	cudaFree(drec_y);
	cudaFree(drec_x);

	free(hrec_uid);
	free(hrec_z);
	free(hrec_y);
	free(hrec_x);

	cudaFree(dloc_z);
	cudaFree(dloc_y);
	cudaFree(dloc_x);

	free(hloc_z);
	free(hloc_y);
	free(hloc_x);
}

/**
 *
 */
void imprimeResultado(float radio) {
	FILE * fh;

	fh = fopen("/devel/salidav3.txt", "w");
	for (int i = 0; i < cantiloc; i++) {
		PLocalidad pl = (ploc + i);
		for (int tema = 0; tema < CANTI_TIPO_REC; tema++) {
			float distancia = *(hdist_resultado + (i * CANTI_TIPO_REC) + tema);
			int j = *(hidrec_resultado + (i * CANTI_TIPO_REC) + tema);
			PRecurso pr = (prec + j);

			fprintf(fh, "%d,%d,%d,%s,%d,%lf,%d,%d,%d,0\n", pl->est, pl->mun,
					pl->loc, (pdic + tema)->nombre, pl->pob, radio * distancia,
					pr->est, pr->mun, pr->loc);
		}
	}

	fclose(fh);
}
