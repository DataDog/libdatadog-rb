// Minimal smoke test for the libdatadog Rust↔C FFI.
// Creates a tag vector, pushes a tag, and verifies the round-trip works.

#include <stdio.h>
#include <datadog/common.h>

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

    printf("OK: libdatadog FFI smoke test passed\n");
    return 0;
}
