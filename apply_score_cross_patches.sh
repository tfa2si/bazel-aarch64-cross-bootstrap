#!/bin/bash
set -e

SCORE_COMM_SRC=/home/bluebox/score/communication
WORKSPACE=/home/bluebox/test/communication
SCORE_BASELIBS=/home/bluebox/score_forks/score_baselibs

# ---------------------------------------------------------------------------
# 1. Copy rebuilt libacl.a and headers into the forked score_baselibs
# ---------------------------------------------------------------------------
cp ~/acl_build/acl-*/.libs/libacl.a "$SCORE_BASELIBS/third_party/acl/local_acl/"
cp ~/acl_build/acl-*/include/acl/*.h "$SCORE_BASELIBS/third_party/acl/local_acl/include/acl/"

# ---------------------------------------------------------------------------
# 2. Patch sysroot header: remove EXPORT macros from sys/acl.h
# ---------------------------------------------------------------------------
sudo sed -i 's/^EXPORT //;s/ EXPORT / /g;s/^EXPORT$//g' /usr/aarch64-linux-gnu/include/sys/acl.h

# ---------------------------------------------------------------------------
# 3. Patch local_acl header: remove EXPORT macros from libacl.h
# ---------------------------------------------------------------------------
sed -i 's/^EXPORT //;s/ EXPORT / /g;s/^EXPORT$//g' \
    "$SCORE_BASELIBS/third_party/acl/local_acl/include/acl/libacl.h"

# ---------------------------------------------------------------------------
# 4. Patch score_baselibs BUILD to use local_acl for ARM64
# ---------------------------------------------------------------------------
sed -i 's|@platforms//cpu:aarch64\": ".*acl.*|@platforms//cpu:aarch64\": "//third_party/acl/local_acl:acl",|' \
    "$SCORE_BASELIBS/third_party/acl/BUILD"

# ---------------------------------------------------------------------------
# 5. Ensure Bazel disables -Werror=deprecated-declarations in workspace
# ---------------------------------------------------------------------------
if ! grep -q -- '--copt=-Wno-error=deprecated-declarations' "$WORKSPACE/.bazelrc" 2>/dev/null; then
    echo 'build --copt=-Wno-error=deprecated-declarations' >> "$WORKSPACE/.bazelrc"
fi

# ---------------------------------------------------------------------------
# 6. Copy platforms/, toolchain/, local_libs/ into workspace if missing
# ---------------------------------------------------------------------------
[ -d "$WORKSPACE/platforms" ] || cp -r "$SCORE_COMM_SRC/platforms" "$WORKSPACE/"
[ -d "$WORKSPACE/toolchain" ] || cp -r "$SCORE_COMM_SRC/toolchain" "$WORKSPACE/"
[ -d "$WORKSPACE/local_libs" ] || cp -r "$SCORE_COMM_SRC/local_libs" "$WORKSPACE/"
if [ -d "$SCORE_COMM_SRC/third_party/acl_arm64_local" ] && \
   [ ! -d "$WORKSPACE/third_party/acl_arm64_local" ]; then
    cp -r "$SCORE_COMM_SRC/third_party/acl_arm64_local" "$WORKSPACE/third_party/"
fi

# ---------------------------------------------------------------------------
# 7. Add toolchain registration + overrides to MODULE.bazel if not present
# ---------------------------------------------------------------------------
MODULE="$WORKSPACE/MODULE.bazel"
if ! grep -q 'register_toolchains("//toolchain:arm64_linux_gcc_toolchain_entry")' "$MODULE"; then
    sed -i '/^module(/a \
\
# Register minimal cross toolchain and platforms\
register_toolchains("//toolchain:arm64_linux_gcc_toolchain_entry")\
register_execution_platforms("//platforms:local_x86_64", "//platforms:rpi5_aarch64")\
\
# Override score_baselibs with local fork\
local_path_override(\
    module_name = "score_baselibs",\
    path = "'"$SCORE_BASELIBS"'",\
)\
\
# Make local_acl visible to all modules (including score_baselibs)\
bazel_dep(name = "local_acl", version = "1.0")\
local_path_override(\
    module_name = "local_acl",\
    path = "./local_libs/acl",\
)' "$MODULE"
fi

# ---------------------------------------------------------------------------
# 8. Fix tracing_runtime.cpp: replace StdVariantType usage with direct field
#    assignment (score::cpp::variant has no in_place_index constructor)
# ---------------------------------------------------------------------------
TRACING="$WORKSPACE/score/mw/com/impl/bindings/lola/tracing/tracing_runtime.cpp"
if grep -q 'StdVariantType element_variant' "$TRACING"; then
python3 - <<'PYEOF'
import re, sys

path = "/home/bluebox/test/communication/score/mw/com/impl/bindings/lola/tracing/tracing_runtime.cpp"
with open(path) as f:
    src = f.read()

old = re.search(
    r'// Compute element variant.*?return ServiceInstanceElement\{[^}]+\};',
    src, re.DOTALL)
if not old:
    print("tracing_runtime.cpp: pattern not found, skipping")
    sys.exit(0)

new_code = '''    ServiceInstanceElement output_service_instance_element{};
    if (service_element_type == impl::ServiceElementType::EVENT)
    {
        const auto lola_event_id = lola_service_type_deployment->events_.at(std::string{service_element_name});
        output_service_instance_element.element_id = static_cast<ServiceInstanceElement::EventIdType>(lola_event_id);
    }
    else if (service_element_type == impl::ServiceElementType::FIELD)
    {
        const auto lola_field_id = lola_service_type_deployment->fields_.at(std::string{service_element_name});
        output_service_instance_element.element_id = static_cast<ServiceInstanceElement::FieldIdType>(lola_field_id);
    }
    else
    {
        score::mw::log::LogFatal("lola") << "Service element type: " << service_element_type
                                         << " is invalid. Terminating.";
        std::terminate();
    }

    output_service_instance_element.service_id =
        static_cast<ServiceInstanceElement::ServiceIdType>(lola_service_type_deployment->service_id_);

    if (!lola_service_instance_deployment->instance_id_.has_value())
    {
        score::mw::log::LogFatal("lola")
            << "Tracing should not be done on service element without configured instance ID. Terminating.";
        std::terminate();
    }
    output_service_instance_element.instance_id = static_cast<ServiceInstanceElement::InstanceIdType>(
        lola_service_instance_deployment->instance_id_.value().GetId());

    const auto version = ServiceIdentifierTypeView{service_identifier}.GetVersion();
    output_service_instance_element.major_version = ServiceVersionTypeView{version}.getMajor();
    output_service_instance_element.minor_version = ServiceVersionTypeView{version}.getMinor();
    return output_service_instance_element;'''

src = src[:old.start()] + new_code + src[old.end():]
with open(path, 'w') as f:
    f.write(src)
print("tracing_runtime.cpp: patched OK")
PYEOF
fi

# ---------------------------------------------------------------------------
# 9. Fix flag_file.cpp: ResultBlank instead of Result<void>
# ---------------------------------------------------------------------------
FLAG_FILE="$WORKSPACE/score/mw/com/impl/bindings/lola/service_discovery/flag_file.cpp"
sed -i \
    -e 's/score::Result<void> result{}/score::ResultBlank result{}/g' \
    -e 's/result = Result<void>{}/result = ResultBlank{}/g' \
    "$FLAG_FILE"

# ---------------------------------------------------------------------------
# 10. Ensure toolchain cc_toolchain_config.bzl has link_libstdcpp_feature
# ---------------------------------------------------------------------------
TOOLCHAIN_CFG="$WORKSPACE/toolchain/cc_toolchain_config.bzl"
if ! grep -q 'link_libstdcpp' "$TOOLCHAIN_CFG"; then
python3 - <<'PYEOF'
path = "/home/bluebox/test/communication/toolchain/cc_toolchain_config.bzl"
with open(path) as f:
    src = f.read()

insert_after = '    )\n\n    return cc_common.create_cc_toolchain_config_info('
new_feature = '''    )

    link_libstdcpp_feature = feature(
        name = "link_libstdcpp",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = ["c++-link-executable", "c++-link-dynamic-library", "c++-link-nodeps-dynamic-library"],
                flag_groups = [
                    flag_group(flags = ["-lstdc++", "-lm", "-lrt", "-latomic"]),
                ],
            ),
        ],
    )

    return cc_common.create_cc_toolchain_config_info('''

src = src.replace(insert_after, new_feature, 1)
src = src.replace(
    "        features = [\n            with_sysroot_feature,\n        ],",
    "        features = [\n            with_sysroot_feature,\n            link_libstdcpp_feature,\n        ],"
)

with open(path, 'w') as f:
    f.write(src)
print("cc_toolchain_config.bzl: patched OK")
PYEOF
fi

# ---------------------------------------------------------------------------
# 11. Add console_only_backend dep to ipc_bridge_cpp BUILD if missing
# ---------------------------------------------------------------------------
IPC_BUILD="$WORKSPACE/score/mw/com/example/ipc_bridge/BUILD"
if ! grep -q 'console_only_backend' "$IPC_BUILD"; then
    sed -i 's|"@score_baselibs//score/mw/log",|"@score_baselibs//score/mw/log",\n        "@score_baselibs//score/mw/log:console_only_backend",|' \
        "$IPC_BUILD"
fi

echo "All cross-compilation patches applied."
