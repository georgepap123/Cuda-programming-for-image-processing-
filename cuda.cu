#include <stdio.h>
#include <cuda_runtime.h>
#include <jpeglib.h>

__global__ void remove_red_green(unsigned char *input, unsigned char *output, int width, int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;

    if (x < width && y < height) {
        int index = y * width + x;
        output[index * 3] = 0;
        output[index * 3 + 1] = 0;
        output[index * 3 + 2] = input[index * 3 + 2];
    }
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        printf("Usage: %s input_file output_file\n", argv[0]);
        return 1;
    }

    // Open input file
    FILE *input_file = fopen(argv[1], "rb");
    if (!input_file) {
        printf("Error: Failed to open input file\n");
        return 1;
    }

    // Read JPEG header
    struct jpeg_decompress_struct cinfo;
    struct jpeg_error_mgr jerr;
    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_decompress(&cinfo);
    jpeg_stdio_src(&cinfo, input_file);
    jpeg_read_header(&cinfo, TRUE);

    // Allocate memory for image data
    int width = cinfo.image_width;
    int height = cinfo.image_height;
    int size = width * height * 3;
    unsigned char *input = (unsigned char *)malloc(size);
    unsigned char *output = (unsigned char *)malloc(size);

    // Read image data
    jpeg_start_decompress(&cinfo);
    while (cinfo.output_scanline < cinfo.output_height) {
        unsigned char *buffer[1];
        buffer[0] = input + cinfo.output_scanline * width * 3;
        jpeg_read_scanlines(&cinfo, buffer, 1);
    }
    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);
    fclose(input_file);

    // Allocate memory on GPU
    unsigned char *input_gpu, *output_gpu;
    cudaMalloc(&input_gpu, size);
    cudaMalloc(&output_gpu, size);

    // Copy data to GPU
    cudaMemcpy(input_gpu, input, size, cudaMemcpyHostToDevice);

    // Launch kernel
    dim3 block(16, 16);
    dim3 grid((width + block.x - 1) / block.x, (height + block.y - 1) / block.y);
    remove_red_green<<<grid, block>>>(input_gpu, output_gpu, width, height);
   // Copy data back from GPU
cudaMemcpy(output, output_gpu, size, cudaMemcpyDeviceToHost);

// Open output file
FILE *output_file = fopen(argv[2], "wb");
if (!output_file) {
    printf("Error: Failed to open output file\n");
    return 1;
}

// Write JPEG header
struct jpeg_compress_struct cinfo_out;
struct jpeg_error_mgr jerr_out;
cinfo_out.err = jpeg_std_error(&jerr_out);
jpeg_create_compress(&cinfo_out);
jpeg_stdio_dest(&cinfo_out, output_file);
cinfo_out.image_width = width;
cinfo_out.image_height = height;
cinfo_out.input_components = 3;
cinfo_out.in_color_space = JCS_RGB;
jpeg_set_defaults(&cinfo_out);
jpeg_set_quality(&cinfo_out, 100, TRUE);
jpeg_start_compress(&cinfo_out, TRUE);

// Write image data
while (cinfo_out.next_scanline < cinfo_out.image_height) {

     unsigned char *buffer[1];
    buffer[0] = output + cinfo_out.next_scanline * width * 3;
    jpeg_write_scanlines(&cinfo_out, buffer, 1);
}
jpeg_finish_compress(&cinfo_out);
jpeg_destroy_compress(&cinfo_out);
fclose(output_file);

// Free memory
free(input);
free(output);
cudaFree(input_gpu);
cudaFree(output_gpu);

return 0;
}