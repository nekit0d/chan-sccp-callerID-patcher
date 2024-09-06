#!/bin/bash

# Проверяем, что передан аргумент
if [ "$#" -ne 1 ]; then
    echo "Использование: $0 Каталог исходников chan-sccp"
    exit 1
fi

# Указываем путь к файлу
PROJECT_DIR="$1"
VERSION_FILE="${PROJECT_DIR}/.version"
HH_FILE="${PROJECT_DIR}/src/sccp_config_entries.hh"
CONF_FILE="${PROJECT_DIR}/conf/sccp.conf.annotated"
DEVICE_H_FILE="${PROJECT_DIR}/src/sccp_device.h"
DEVICE_C_FILE="${PROJECT_DIR}/src/sccp_device.c"
PROTOCOL_C_FILE="${PROJECT_DIR}/src/sccp_protocol.c"

# Проверяем, существует ли файл
if [[ ! -f "$FILE" ]]; then
    echo "Файл не найден: $FILE"
    exit 1
fi

# Проверяем, что версия в файле .version равна 4.3.5
VERSION=$(cat "$VERSION_FILE")
EXPECTED_VERSION="4.3.5"

if [[ "$VERSION" != "$EXPECTED_VERSION" ]]; then
    echo "Неверная версия: $VERSION. Ожидалась версия: $EXPECTED_VERSION."
    exit 1
fi

# Создаем резервную копию файла с добавлением .bak
HH_BACKUP_FILE="${HH_FILE}.old"
cp "$HH_FILE" "$HH_BACKUP_FILE"
echo "Создана резервная копия файла: $HH_BACKUP_FILE"

# Используем sed для замены строк внутри блока #ifdef HAVE_ICONV
sed -i '/#ifdef HAVE_ICONV/,/#endif/ {
    s#"phonecodepage",\s*G_OBJ_REF(iconvcodepage),\s*TYPE_STRINGPTR,\s*SCCP_CONFIG_FLAG_NONE,\s*SCCP_CONFIG_NOUPDATENEEDED,\s*"ISO8859-1"#"phonecodepage", G_OBJ_REF(iconvcodepage), TYPE_STRINGPTR, SCCP_CONFIG_FLAG_NONE, SCCP_CONFIG_NOUPDATENEEDED, "CP1251"#g
}' "$HH_FILE"

# Сообщаем об успешной замене
echo "Строки заменены в файле: $HH_FILE"


# Проверяем, существует ли файл sccp.conf.annotated
if [[ ! -f "$CONF_FILE" ]]; then
    echo "Файл конфигурации не найден: $CONF_FILE"
    exit 1
fi

# Создаем резервную копию файла конфигурации
CONF_BACKUP_FILE="${CONF_FILE}.old"
cp "$CONF_FILE" "$CONF_BACKUP_FILE"
echo "Создана резервная копия файла конфигурации: $CONF_BACKUP_FILE"

# Замена строки в файле конфигурации
sed -i 's|phonecodepage = ""|phonecodepage = "CP1251"|' "$CONF_FILE"

# Сообщаем об успешной замене
echo "Замена строки выполнена в файле конфигурации: $CONF_FILE"

# Создаем резервную копию файла sccp_device.h
DEVICE_BACKUP_FILE="${DEVICE_H_FILE}.old"
cp "$DEVICE_H_FILE" "$DEVICE_BACKUP_FILE"
echo "Создана резервная копия файла: $DEVICE_BACKUP_FILE"

# Добавление функции Locale_CallerID в структуру sccp_device
sed -i '/^struct sccp_device {/,/};/{
/void (\*copyStr2Locale)/{
     a\
#if HAVE_ICONV\
    void (*Locale_CallerID)(constDevicePtr d, char *dst, ICONV_CONST char *src, size_t dst_size); /* copy string to device converted to locale if necessary to CallerID */\
#endif
    }
}' "$DEVICE_H_FILE"

# Сообщаем об успешном добавлении
echo "Добавлена функция Locale_CallerID в файл: $DEVICE_H_FILE"

# Создаем резервную копию файла sccp_device.c
DEVICE_C_BACKUP_FILE="${DEVICE_C_FILE}.old"
cp "$DEVICE_C_FILE" "$DEVICE_C_BACKUP_FILE"
echo "Создана резервная копия файла: $DEVICE_C_BACKUP_FILE"

# Добавление Locale_CallerID в sccp_device_create в sccp_device_preregistration
# Добавление функции sccp_device_Locale_CallerID_Convert
sed -i '/void sccp_device_preregistration(devicePtr device)/,/^void/ {
    /device->copyStr2Locale = sccp_device_copyStr2Locale_Convert/ a\
        device->Locale_CallerID = sccp_device_Locale_CallerID_Convert;
}
/^devicePtr sccp_device_create(const char \* id)/,/return d\;/ {
    /d->copyStr2Locale = sccp_device_copyStr2Locale_UTF8;/ a\
#if HAVE_ICONV\
    d->Locale_CallerID = sccp_device_copyStr2Locale_UTF8;\
#endif
}
/^#if HAVE_ICONV/,/#endif/ {
    /static void sccp_device_copyStr2Locale_Convert(constDevicePtr d, char \*dst, ICONV_CONST char \*src, size_t dst_size)/{
        i\
static void sccp_device_Locale_CallerID_Convert(constDevicePtr d, char *dst, ICONV_CONST char *src, size_t dst_size)\
{\
    pbx_assert(NULL != dst && NULL != src);\
    char *buf = (char *)sccp_alloca(dst_size);\
    size_t buf_len = dst_size;\
    memset(buf, 0, dst_size);\
    if (sccp_device_convUtf8toLatin1(d, src, buf, buf_len)) {\
        int len = sccp_strlen(buf);\
        while (len-- != 0) {\
            if ((unsigned char)(*buf) >= 0xC0 && (unsigned char)(*buf) <= 0xFF) {\
                *dst = 0xC3; /* Добавочный символ для русского алфавита */\
                dst++;\
            }\
            if ((unsigned char)(*buf) == 0xA8 || (unsigned char)(*buf) == 0xB8) {\
                *dst = 0xC1; /* символ Ё */\
                dst++;\
            }\
            *dst++ = *buf++;\
        }\
        *dst = '\0';\
        return;\
    }\
}\
\

    }
}' "$DEVICE_C_FILE"

# Сообщаем об успешном добавлении функции
echo "Добавлена функция sccp_device_Locale_CallerID_Convert и Добавление Locale_CallerID в sccp_device_create в sccp_device_preregistration в файл: $DEVICE_C_FILE"

# Создаем резервную копию файла sccp_device.c
PROTOCOL_C_BACKUP_FILE="${PROTOCOL_C_FILE}.old"
cp "$PROTOCOL_C_FILE" "$PROTOCOL_C_BACKUP_FILE"
echo "Создана резервная копия файла: $PROTOCOL_C_BACKUP_FILE"

# Вставка блока в sccp_protocol.c
sed -i '/static void sccp_protocol_sendCallInfoV7 (const sccp_callinfo_t/,/sccp_dev_send(device, msg)\;/ {
    /iCallInfo.Getter(ci,/,/for (i = 0; i < dataSize; i++) {/ {
        /for (i = 0; i < dataSize; i++) {/ {
            i\
#if HAVE_ICONV\
    // Будем конвертить строки\
    char data_buf[StationMaxNameSize]; // Буфер для конвертации кодировки строки\
    int index;\
    memset(data_buf, 0, StationMaxNameSize);\
    index=8;\
    sccp_copy_string(data_buf,(char *)data[index],StationMaxNameSize);\
    device->Locale_CallerID(device, data[index], data_buf,  sccp_strlen(data_buf));\
    index++;\
    sccp_copy_string(data_buf,(char *)data[index],StationMaxNameSize);\
    device->Locale_CallerID(device, data[index], data_buf,  sccp_strlen(data_buf));\
    index++;\
    sccp_copy_string(data_buf,(char *)data[index],StationMaxNameSize);\
    device->Locale_CallerID(device, data[index], data_buf,  sccp_strlen(data_buf));\
    index++;\
    sccp_copy_string(data_buf,(char *)data[index],StationMaxNameSize);\
    device->Locale_CallerID(device, data[index], data_buf,  sccp_strlen(data_buf));\
    sccp_dump_packet((unsigned char *) data, StationMaxNameSize*dataSize);\
#endif\

        }
    }
}' "$PROTOCOL_C_FILE"

echo "Добавлен блок конвертации в файл: $PROTOCOL_C_FILE"
