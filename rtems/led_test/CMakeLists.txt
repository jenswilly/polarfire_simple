# polarfire_simple LED test for RTEMS 6.2 (riscv/mpfs64imafdc, U54_1 via HSS).
# Same function as the bare-metal softconsole/led_test.
#
# Build in the devcontainer:
#   cmake -S rtems/led_test -B rtems/led_test/build -G Ninja
#   cmake --build rtems/led_test/build
# Output: build/led_test.elf and the HSS boot image build/payload.bin

cmake_minimum_required(VERSION 3.20)

set(RTEMS_CONFIG_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../rtems-cmake"
    CACHE FILEPATH "Directory containing the rtems-cmake *.cmake files")
set(RTEMS_PREFIX "/opt/rtems/6" CACHE PATH "RTEMS tools and BSP prefix")
set(RTEMS_BSP "riscv/mpfs64imafdc" CACHE STRING "RTEMS BSP")
set(RTEMS_VERSION 6)

include(${RTEMS_CONFIG_DIR}/RTEMSPreProjectConfig.cmake)
rtems_pre_project_config(${RTEMS_PREFIX} ${RTEMS_BSP})
set(CMAKE_TOOLCHAIN_FILE ${RTEMS_CONFIG_DIR}/RTEMSToolchain.cmake)

project(led_test C)

add_executable(led_test src/init.c)
set_target_properties(led_test PROPERTIES SUFFIX ".elf")
target_compile_options(led_test PRIVATE -Wall -Wextra -O2 -g)

include(${RTEMS_CONFIG_DIR}/RTEMSPostProjectConfig.cmake)
rtems_post_project_config(led_test)

# HSS boot image (exec address, hart and privilege mode in hss-payload.yaml)
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/payload.bin
    COMMAND hss-payload-generator -c ${CMAKE_CURRENT_SOURCE_DIR}/hss-payload.yaml
            ${CMAKE_BINARY_DIR}/payload.bin
    DEPENDS led_test ${CMAKE_CURRENT_SOURCE_DIR}/hss-payload.yaml
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Generating HSS boot image payload.bin"
    VERBATIM)
add_custom_target(payload ALL DEPENDS ${CMAKE_BINARY_DIR}/payload.bin)
