#ifndef MEMORYADAPTER_H
#define MEMORYADAPTER_H

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <errno.h>
#include <string.h>
#include <sys/syslog.h>
#include <unistd.h>

#include <systemd/sd-journal.h>

#include "IAdapter.h"

#include "../Helpers/Helpers.h"

class MemoryAdapter : public IAdapter
{
protected:
    void* baseAddress;

public:
    void ReadDescriptions(std::string descriptionFile)
    {
        UNUSED(descriptionFile);
    }

    void CheckDevices() {}

    void ReadByte(uint8_t data)
    {
        UNUSED(data);
    }
    void WriteByte(uint8_t data)
    {
        UNUSED(data);
    }

    void	WriteWord(unsigned reg, uint16_t val)
    {
		volatile uint32_t* ptr = (uint32_t*)baseAddress;
        ptr[reg] = val;
    }
    
    void ReadBlock(uint8_t *data, unsigned int length)
    {
        UNUSED(data);
        UNUSED(length);
    }

    void WriteBlock(uint8_t *data, unsigned int length)
    {
        UNUSED(data);
        UNUSED(length);
    }

    void* MemoryMap(uint32_t address, uint32_t size)
    {
        baseAddress = (uint32_t *)address;

        // TODO: Check if alignment is required
        int fd = open("/dev/mem", O_RDWR | O_SYNC);
        if (fd == -1)
        {
            std::string _statusMessage = "Error (open /dev/mem): " + std::string(strerror(errno));
            syslog (LOG_ERR, "%s", _statusMessage.c_str());
            return (void*)-1;
        }

        void* result = mmap((void*)address, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, address);
        if(result == (void*)-1)
        {
            // TODO: Add error log
            std::string message = "Cannot map memory to address: " + std::to_string(address);
            sd_journal_print(LOG_INFO, message.c_str(), (unsigned long)getpid());
        }
		
		baseAddress = result;

        return result;
    }

    int MemoryUnmap(uint32_t address, uint32_t size)
    {
        return munmap((void*)address, size);
    }

    virtual void Execute()
    {

    }
};

#endif // MEMORYADAPTER_H
