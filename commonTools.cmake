
function(JOIN VALUES GLUE OUTPUT)
  string (REGEX REPLACE "([^\\]|^);" "\\1${GLUE}" _TMP_STR "${VALUES}")
  string (REGEX REPLACE "[\\](.)" "\\1" _TMP_STR "${_TMP_STR}") #fixes escaping
  set (${OUTPUT} "${_TMP_STR}" PARENT_SCOPE)
endfunction()

# move translation files
function(deployTr)
    deployTrFromPath(INPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/translate")
endfunction()

function(deployTrFromPath)
    cmake_parse_arguments(PARSED_ARGS "" "INPUT_DIR" "" ${ARGN})

    if(NOT PARSED_ARGS_INPUT_DIR)
        message(FATAL_ERROR "You must provide INPUT_DIR")
    endif()

    if(WIN32 OR LINUX)
        file(COPY "${PARSED_ARGS_INPUT_DIR}/"
            DESTINATION ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/translations
            FILES_MATCHING
                PATTERN "*.qm"
        )
        message(STATUS "Move tr-files ${PARSED_ARGS_INPUT_DIR} => ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}")

        install(DIRECTORY "${PARSED_ARGS_INPUT_DIR}/"
            DESTINATION "translations"
            FILES_MATCHING
                PATTERN "*.qm")
    endif()
endfunction()

# move headers to build directory
function(moveHeaders)
    file(COPY ${CMAKE_CURRENT_SOURCE_DIR}/
        DESTINATION ${CMAKE_BINARY_DIR}/include/${PROJECT_NAME}/${PROJECT_NAME}
        FILES_MATCHING
            PATTERN "*.h"
            PATTERN "*.hpp"
    )
endfunction()


function(generateTarget)
    cmake_parse_arguments(PARSED_ARGS "" "OUTPUT_TARGETS_VAR;PROJECT_TYPE" "TARGETS" ${ARGN})

    if(NOT PARSED_ARGS_OUTPUT_TARGETS_VAR)
        message(FATAL_ERROR "You must provide OUTPUT_TARGETS_VAR")
    endif()

    if(NOT PARSED_ARGS_TARGETS)
        message(FATAL_ERROR "You must provide TARGETS list")
    endif()

    if(NOT PARSED_ARGS_PROJECT_TYPE)
        set(PARSED_ARGS_PROJECT_TYPE "SHARED_LIBRARY")
    endif()

    foreach(TARGET ${PARSED_ARGS_TARGETS})
        set(POSTFIX "")

        if(WIN32)
            if(MSVC_TOOLSET_VERSION)
                set(POSTFIX "${POSTFIX}-vc${MSVC_TOOLSET_VERSION}")
            endif()

            if(SYSTEM_X64)
                set(POSTFIX "${POSTFIX}-amd64")
            endif()

            if(PROJECT_TYPE STREQUAL "EXECUTABLE")
                #nope
            else()
                set(POSTFIX "${POSTFIX}-mt")
            endif()
        endif(WIN32)

        if(CMAKE_BUILD_TYPE STREQUAL "Debug")
            set(POSTFIX "${POSTFIX}-d")
        endif()

        set(RESULT "${PROJECT_PREFIX}${TARGET}${POSTFIX}")

        list(APPEND OUTPUT_TARGETS "${RESULT}")
    endforeach()

    set(${PARSED_ARGS_OUTPUT_TARGETS_VAR} ${OUTPUT_TARGETS} PARENT_SCOPE)
endfunction()

function(aviaNames)
    get_target_property(PROJECT_TYPE ${PROJECT_NAME} TYPE)
    generateTarget(TARGETS ${PROJECT_NAME} OUTPUT_TARGETS_VAR OUTPUT_NAME PROJECT_TYPE ${PROJECT_TYPE})
    set_target_properties(${PROJECT_NAME} PROPERTIES OUTPUT_NAME "${OUTPUT_NAME}")
endfunction()

function(makeAI)
    if(BUILD_VERSION)
        string(TIMESTAMP COMPILE_DATE "%d.%m.%Y")
        string(TIMESTAMP COMPILE_TIME "%H:%M:%S")

        if(NOT PROJECT_VERSION)
            set(PROJECT_VERSION ${CMAKE_PROJECT_VERSION})
            set(PROJECT_VERSION_MAJOR ${CMAKE_PROJECT_VERSION_MAJOR})
            set(PROJECT_VERSION_MINOR ${CMAKE_PROJECT_VERSION_MINOR})
            set(PROJECT_VERSION_PATCH ${CMAKE_PROJECT_VERSION_PATCH})
        endif()

        get_target_property(PROJECT_TYPE ${PROJECT_NAME} TYPE)
        if(PROJECT_TYPE STREQUAL "EXECUTABLE")
            if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_NAME}.ico")
                set(ICON_INCLUDE_TEXT "IDI_ICON1 ICON DISCARDABLE \"${PROJECT_NAME}.ico\"")
            endif()
            configure_file("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/rc_app.in" "${CMAKE_CURRENT_BINARY_DIR}/rc.rc")
        else()
            configure_file("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/rc_lib.in" "${CMAKE_CURRENT_BINARY_DIR}/rc.rc")
        endif()

        target_sources(${PROJECT_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/rc.rc")
        configure_file("${CMAKE_CURRENT_FUNCTION_LIST_DIR}/buildNumber.h.in" "${CMAKE_CURRENT_BINARY_DIR}/buildNumber.h")
    else()
        message(FATAL_ERROR "Variable BUILD_VERSION not found")
    endif(BUILD_VERSION)
endfunction()

# deployqt
function(deployTargets)
    cmake_parse_arguments(PARSED_ARGS "" "SUBDIR;MAINTARGET" "TARGETS" ${ARGN})

    if(WIN32)
        # search windeployqt.exe
        if(Qt5_FOUND AND WIN32 AND TARGET Qt5::qmake AND NOT TARGET Qt5::windeployqt)
            get_target_property(_qt5_qmake_location Qt5::qmake IMPORTED_LOCATION)

            execute_process(
                COMMAND "${_qt5_qmake_location}" -query QT_INSTALL_PREFIX
                RESULT_VARIABLE return_code
                OUTPUT_VARIABLE qt5_install_prefix
                OUTPUT_STRIP_TRAILING_WHITESPACE
            )

            set(DEPLOY_TOOL_PATH "${qt5_install_prefix}/bin/windeployqt.exe")
        endif()

        JOIN("${PARSED_ARGS_TARGETS}" " " TARGETS_JOIN_LIST)
        message(STATUS "Targets to deploy [${TARGETS_JOIN_LIST}]")
        foreach(DEPLOY_TARGET ${PARSED_ARGS_TARGETS})
            list(APPEND DEPLOY_TARGETS "\${CMAKE_INSTALL_PREFIX}/${PARSED_ARGS_SUBDIR}\$<TARGET_FILE_NAME:${DEPLOY_TARGET}>")
        endforeach()

        install(CODE "set(DEPLOY_TOOL_PATH \"${DEPLOY_TOOL_PATH}\")")
        install(CODE "set(DEPLOY_TARGETS \"${DEPLOY_TARGETS}\")")
        install(CODE "set(ENV{PATH} ENV{PATH})")
        install(CODE [[
            message("DEPLOY_TOOL_PATH: ${DEPLOY_TOOL_PATH}")
            message("Deploy files:")
            foreach(T ${DEPLOY_TARGETS})
                message(STATUS "DEPLOY_TARGETS: ${T}")
            endforeach()

            execute_process(COMMAND "${DEPLOY_TOOL_PATH}" ${DEPLOY_TARGETS} --dir ${CMAKE_INSTALL_PREFIX} RESULT_VARIABLE ret)
            if(NOT ret EQUAL "0")
                message( FATAL_ERROR "Bad exit status")
            endif()
        ]])

    elseif(LINUX)
        if(NOT PARSED_ARGS_MAINTARGET)
            message(FATAL_ERROR "You must provide MAINTARGET")
        endif()

        if(NOT LINUX_DEPLOY_TOOL)
            message(FATAL_ERROR "You must provide LINUX_DEPLOY_TOOL")
        endif()

        get_target_property(_qt5_qmake_location Qt5::qmake IMPORTED_LOCATION)

        JOIN("${PARSED_ARGS_TARGETS} ${PARSED_ARGS_MAINTARGET}" " " TARGETS_JOIN_LIST)
        message(STATUS "Targets to deploy [${TARGETS_JOIN_LIST}]")
        foreach(DEPLOY_TARGET ${PARSED_ARGS_TARGETS})
            list(APPEND DEPLOY_TARGETS "\${CMAKE_INSTALL_PREFIX}/lib/\$<TARGET_FILE_NAME:${DEPLOY_TARGET}>")
        endforeach()

        install(CODE "set(DEPLOY_TOOL_PATH \"${LINUX_DEPLOY_TOOL}\")")
        install(CODE "set(DEPLOY_TARGETS \"${DEPLOY_TARGETS}\")")
        install(CODE "set(_qt5_qmake_location \"${_qt5_qmake_location}\")")
        install(CODE "set(MAIN_TARGET \"\${CMAKE_INSTALL_PREFIX}/\$<TARGET_FILE_NAME:${PARSED_ARGS_MAINTARGET}>\")")
        #install(CODE "set(ENV{PATH} ENV{PATH})")

        install(CODE [[
            set(APP_BUILD_DIR "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}")
            message(STATUS "DEPLOY_TOOL_PATH: ${DEPLOY_TOOL_PATH}")
            message(STATUS "MAIN_TARGET: ${MAIN_TARGET}")
            message(STATUS "APP_BUILD_DIR: ${APP_BUILD_DIR}")
            set(EXECUTABLE_LIST)
            message(STATUS "Deploy files:")
            foreach(T ${DEPLOY_TARGETS})
                message(STATUS "DEPLOY_TARGETS: ${T}")
                list(APPEND EXECUTABLE_LIST "-executable=${T}")
            endforeach()

            execute_process(COMMAND "${DEPLOY_TOOL_PATH}" "${MAIN_TARGET}" ${EXECUTABLE_LIST} -unsupported-allow-new-glibc
                            "-qmake=${_qt5_qmake_location}"
                            WORKING_DIRECTORY "${APP_BUILD_DIR}" RESULT_VARIABLE ret)
            if(NOT ret EQUAL "0")
                message( FATAL_ERROR "Bad exit status. Error [${ret}]")
            endif()
        ]])
    elseif(APPLE)
        if(NOT PARSED_ARGS_MAINTARGET)
            message(FATAL_ERROR "You must provide MAINTARGET")
        endif()

        get_target_property(QMAKE_LOCATION Qt5::qmake LOCATION)
        get_filename_component(QT_BIN_LOCATION "${QMAKE_LOCATION}" DIRECTORY)
        set(DEPLOY_TOOL_PATH "${QT_BIN_LOCATION}/macdeployqt")

        JOIN("${PARSED_ARGS_TARGETS} ${PARSED_ARGS_MAINTARGET}" " " TARGETS_JOIN_LIST)
        message(STATUS "Targets to deploy [${TARGETS_JOIN_LIST}]")
        foreach(DEPLOY_TARGET ${PARSED_ARGS_TARGETS})
            list(APPEND DEPLOY_TARGETS "\${CMAKE_INSTALL_PREFIX}/lib/\$<TARGET_FILE_NAME:${DEPLOY_TARGET}>")
        endforeach()

        install(CODE "set(DEPLOY_TOOL_PATH \"${DEPLOY_TOOL_PATH}\")")
        install(CODE "set(DEPLOY_TARGETS \"${DEPLOY_TARGETS}\")")
        install(CODE "set(MAIN_TARGET \"\${CMAKE_INSTALL_PREFIX}/\$<TARGET_FILE_NAME:${PARSED_ARGS_MAINTARGET}>.app\")")

        install(CODE [[
            set(APP_BUILD_DIR "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}")
            message(STATUS "DEPLOY_TOOL_PATH: ${DEPLOY_TOOL_PATH}")
            message(STATUS "MAIN_TARGET: ${MAIN_TARGET}")
            message(STATUS "APP_BUILD_DIR: ${APP_BUILD_DIR}")
            set(EXECUTABLE_LIST)
            message(STATUS "Deploy files:")
            foreach(T ${DEPLOY_TARGETS})
                message(STATUS "DEPLOY_TARGETS: ${T}")
                list(APPEND EXECUTABLE_LIST "-executable=${T}")
            endforeach()

            execute_process(COMMAND "${DEPLOY_TOOL_PATH}" "${MAIN_TARGET}" ${EXECUTABLE_LIST} -dmg
                            WORKING_DIRECTORY "${APP_BUILD_DIR}" RESULT_VARIABLE ret)
            if(NOT ret EQUAL "0")
                message( FATAL_ERROR "Bad exit status. Error [${ret}]")
            endif()
        ]])
    endif()
endfunction()

