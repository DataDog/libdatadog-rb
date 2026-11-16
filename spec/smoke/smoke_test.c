// Exercises APIs required by the Ruby tracer in the packaged library.

#include <stdio.h>
#include <string.h>
#include <datadog/common.h>
#include <datadog/data-pipeline.h>
#include <datadog/ffe.h>

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

static int verify_prerequisites(void) {
    const char *json =
        "{\"createdAt\":\"2026-01-01T00:00:00Z\",\"environment\":{\"name\":\"test\"},"
        "\"flags\":{"
        "\"parent\":{\"key\":\"parent\",\"enabled\":true,\"variationType\":\"BOOLEAN\","
        "\"variations\":{\"on\":{\"key\":\"on\",\"value\":true}},"
        "\"allocations\":[{\"key\":\"parent-allocation\",\"doLog\":true,"
        "\"splits\":[{\"variationKey\":\"on\",\"shards\":[]}]}]},"
        "\"root\":{\"key\":\"root\",\"enabled\":true,\"variationType\":\"BOOLEAN\","
        "\"variations\":{\"on\":{\"key\":\"on\",\"value\":true}},"
        "\"allocations\":[{\"key\":\"root-allocation\",\"doLog\":true,"
        "\"rules\":[{\"conditions\":[{\"flagEvaluation\":{\"key\":\"parent\"},"
        "\"operator\":\"ONE_OF\",\"value\":[\"on\"]}]}],"
        "\"splits\":[{\"variationKey\":\"on\",\"shards\":[]}]}]}}}";
    struct ddog_ffe_Result_HandleConfiguration parsed = ddog_ffe_configuration_new(
        (struct ddog_ffe_BorrowedStr){.ptr = (const uint8_t *)json, .len = strlen(json)});
    if (parsed.tag != DDOG_FFE_RESULT_HANDLE_CONFIGURATION_OK_HANDLE_CONFIGURATION) {
        fprintf(stderr, "FAIL: prerequisite configuration could not be parsed\n");
        return 1;
    }

    ddog_ffe_Handle_Configuration configuration = parsed.ok;
    ddog_ffe_Handle_EvaluationContext context = ddog_ffe_evaluation_context_new("subject", NULL, 0);
    ddog_ffe_Handle_ResolutionDetails root = ddog_ffe_get_assignment(
        configuration, "root", DDOG_FFE_EXPECTED_FLAG_TYPE_BOOLEAN, context);
    struct ddog_ffe_BorrowedStr key = ddog_ffe_assignment_dependency_key(root, 0);
    int failed = ddog_ffe_assignment_get_error_code(root) != DDOG_FFE_ERROR_CODE_OK ||
        ddog_ffe_assignment_dependency_count(root) != 1 ||
        ddog_ffe_assignment_dependency_error_code(root, 0) != DDOG_FFE_ERROR_CODE_OK ||
        !ddog_ffe_assignment_dependency_exposure_eligible(root, 0) ||
        key.len != 6 || memcmp(key.ptr, "parent", 6) != 0;
    ddog_ffe_Handle_ResolutionDetails child = ddog_ffe_assignment_dependency_result(root, 0);
    ddog_ffe_assignment_drop(&root);
    ddog_ffe_configuration_drop(&configuration);

    struct ddog_ffe_VariantValue value = ddog_ffe_assignment_get_value(child);
    failed = failed || value.tag != DDOG_FFE_VARIANT_VALUE_BOOLEAN || !value.boolean;
    ddog_ffe_assignment_drop(&child);
    ddog_ffe_evaluation_context_drop(&context);
    if (failed) fprintf(stderr, "FAIL: prerequisite assignment or owned child result was lost\n");
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
    if (verify_prerequisites() != 0) return 1;

    printf("OK: libdatadog FFI smoke test passed\n");
    return 0;
}
