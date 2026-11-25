// Exercises APIs required by the Ruby tracer in the packaged library.

#include <stdio.h>
#include <string.h>
#include <datadog/common.h>
#include <datadog/data-pipeline.h>

static int verify_observations(void) {
    ddog_TraceExporterConfig *config = NULL;
    ddog_trace_exporter_config_new(&config);
    ddog_TraceExporterError *error = ddog_trace_exporter_config_enable_observations(config);
    ddog_trace_exporter_config_free(config);
    if (error != NULL) {
        fprintf(stderr, "FAIL: could not enable exporter observations\n");
        ddog_trace_exporter_error_free(error);
        return 1;
    }

    ddog_TraceExporterObservations observations;
    memset(&observations, 0xff, sizeof(observations));
    ddog_TraceExporterResponse *response = NULL;
    error = ddog_trace_exporter_send_trace_chunks_observed(NULL, NULL, &response, &observations, NULL);
    int failed = error == NULL || response != NULL || observations.requests_count != 0 ||
        observations.bytes_sent != 0 || observations.status_code != 0;
    if (error != NULL) ddog_trace_exporter_error_free(error);
    if (response != NULL) ddog_trace_exporter_response_free(response);
    if (failed) fprintf(stderr, "FAIL: invalid observed send did not initialise its outputs\n");
    return failed;
}

int main(void) {
    ddog_Vec_Tag tags = ddog_Vec_Tag_new();

    ddog_Vec_Tag_PushResult result =
        ddog_Vec_Tag_push(&tags, DDOG_CHARSLICE_C("test.key"), DDOG_CHARSLICE_C("test.value"));

    if (result.tag != DDOG_VEC_TAG_PUSH_RESULT_OK) {
        ddog_CharSlice msg = ddog_Error_message(&result.err);
        fprintf(stderr, "FAIL: ddog_Vec_Tag_push error: %.*s\n", (int)msg.len, msg.ptr);
        ddog_Error_drop(&result.err);
        ddog_Vec_Tag_drop(tags);
        return 1;
    }

    ddog_Vec_Tag_drop(tags);

    if (verify_observations() != 0) return 1;

    printf("OK: libdatadog FFI smoke test passed\n");
    return 0;
}
