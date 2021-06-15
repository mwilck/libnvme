// SPDX-License-Identifier: LGPL-2.1-or-later
/*
 * This file is part of libnvme.
 * Copyright (c) 2020 Western Digital Corporation or its affiliates.
 *
 * Authors: Keith Busch <keith.busch@wdc.com>
 * 	    Chaitanya Kulkarni <chaitanya.kulkarni@wdc.com>
 */

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>

#include <sys/stat.h>
#include <sys/types.h>

#ifdef CONFIG_SYSTEMD
#include <systemd/sd-id128.h>
#define NVME_HOSTNQN_ID SD_ID128_MAKE(c7,f4,61,81,12,be,49,32,8c,83,10,6f,9d,dd,d8,6b)
#endif

#include <ccan/array_size/array_size.h>

#include "fabrics.h"
#include "ioctl.h"
#include "util.h"
#include "log.h"

#define NVMF_HOSTID_SIZE	37

const char *nvmf_dev = "/dev/nvme-fabrics";
const char *nvmf_hostnqn_file = "/etc/nvme/hostnqn";
const char *nvmf_hostid_file = "/etc/nvme/hostid";

const char *arg_str(const char * const *strings,
		size_t array_size, size_t idx)
{
	if (idx < array_size && strings[idx])
		return strings[idx];
	return "unrecognized";
}

const char * const trtypes[] = {
	[NVMF_TRTYPE_RDMA]	= "rdma",
	[NVMF_TRTYPE_FC]	= "fc",
	[NVMF_TRTYPE_TCP]	= "tcp",
	[NVMF_TRTYPE_LOOP]	= "loop",
};

const char *nvmf_trtype_str(__u8 trtype)
{
	return arg_str(trtypes, ARRAY_SIZE(trtypes), trtype);
}

static const char * const adrfams[] = {
	[NVMF_ADDR_FAMILY_PCI]	= "pci",
	[NVMF_ADDR_FAMILY_IP4]	= "ipv4",
	[NVMF_ADDR_FAMILY_IP6]	= "ipv6",
	[NVMF_ADDR_FAMILY_IB]	= "infiniband",
	[NVMF_ADDR_FAMILY_FC]	= "fibre-channel",
};

const char *nvmf_adrfam_str(__u8 adrfam)
{
	return arg_str(adrfams, ARRAY_SIZE(adrfams), adrfam);
}

static const char * const subtypes[] = {
	[NVME_NQN_DISC]		= "discovery subsystem",
	[NVME_NQN_NVME]		= "nvme subsystem",
};

const char *nvmf_subtype_str(__u8 subtype)
{
	return arg_str(subtypes, ARRAY_SIZE(subtypes), subtype);
}

static const char * const treqs[] = {
	[NVMF_TREQ_NOT_SPECIFIED]	= "not specified",
	[NVMF_TREQ_REQUIRED]		= "required",
	[NVMF_TREQ_NOT_REQUIRED]	= "not required",
	[NVMF_TREQ_DISABLE_SQFLOW]	= "not specified, "
					  "sq flow control disable supported",
};

const char *nvmf_treq_str(__u8 treq)
{
	return arg_str(treqs, ARRAY_SIZE(treqs), treq);
}

static const char * const sectypes[] = {
	[NVMF_TCP_SECTYPE_NONE]		= "none",
	[NVMF_TCP_SECTYPE_TLS]		= "tls",
};

const char *nvmf_sectype_str(__u8 sectype)
{
	return arg_str(sectypes, ARRAY_SIZE(sectypes), sectype);
}

static const char * const prtypes[] = {
	[NVMF_RDMA_PRTYPE_NOT_SPECIFIED]	= "not specified",
	[NVMF_RDMA_PRTYPE_IB]			= "infiniband",
	[NVMF_RDMA_PRTYPE_ROCE]			= "roce",
	[NVMF_RDMA_PRTYPE_ROCEV2]		= "roce-v2",
	[NVMF_RDMA_PRTYPE_IWARP]		= "iwarp",
};

const char *nvmf_prtype_str(__u8 prtype)
{
	return arg_str(prtypes, ARRAY_SIZE(prtypes), prtype);
}

static const char * const qptypes[] = {
	[NVMF_RDMA_QPTYPE_CONNECTED]	= "connected",
	[NVMF_RDMA_QPTYPE_DATAGRAM]	= "datagram",
};

const char *nvmf_qptype_str(__u8 qptype)
{
	return arg_str(qptypes, ARRAY_SIZE(qptypes), qptype);
}

static const char * const cms[] = {
	[NVMF_RDMA_CMS_RDMA_CM]	= "rdma-cm",
};

const char *nvmf_cms_str(__u8 cm)
{
	return arg_str(cms, ARRAY_SIZE(cms), cm);
}

static int add_bool_argument(char **argstr, char *tok, bool arg)
{
	char *nstr;

	if (!arg)
		return 0;
	if (asprintf(&nstr, "%s,%s", *argstr, tok) < 0) {
		errno = ENOMEM;
		return -1;
	}
	free(*argstr);
	*argstr = nstr;

	return 0;
}

static int add_int_argument(char **argstr, char *tok, int arg, bool allow_zero)
{
	char *nstr;

	if (arg < 0 || (!arg && !allow_zero))
		return 0;
	if (asprintf(&nstr, "%s,%s=%d", *argstr, tok, arg) < 0) {
		errno = ENOMEM;
		return -1;
	}
	free(*argstr);
	*argstr = nstr;

	return 0;
}

static int add_argument(char **argstr, const char *tok, const char *arg)
{
	char *nstr;

	if (!(arg && strcmp(arg, "none")))
		return 0;
	if (asprintf(&nstr, "%s,%s=%s", *argstr, tok, arg) < 0) {
		errno = ENOMEM;
		return -1;
	}
	free(*argstr);
	*argstr = nstr;

	return 0;
}

static int build_options(nvme_ctrl_t c, char **argstr,
			 const struct nvme_fabrics_config *cfg)
{
	const char *transport = nvme_ctrl_get_transport(c);
	const char *hostnqn, *hostid;

	if (!transport) {
		nvme_msg(LOG_ERR, "need a transport (-t) argument\n");
		errno = EINVAL;
		return -1;
	}

	if (strncmp(transport, "loop", 4)) {
		if (!nvme_ctrl_get_traddr(c)) {
			nvme_msg(LOG_ERR, "need a address (-a) argument\n");
			errno = EINVAL;
			return -1;
		}
	}

	/* always specify nqn as first arg - this will init the string */
	if (asprintf(argstr, "nqn=%s",
		     nvme_ctrl_get_subsysnqn(c)) < 0) {
		errno = ENOMEM;
		return -1;
	}

	hostnqn = nvme_ctrl_get_hostnqn(c);
	hostid = nvme_ctrl_get_hostid(c);
	if (add_argument(argstr, "transport", transport) ||
	    add_argument(argstr, "traddr",
			 nvme_ctrl_get_traddr(c)) ||
	    add_argument(argstr, "host_traddr",
			 nvme_ctrl_get_host_traddr(c)) ||
	    add_argument(argstr, "trsvcid",
			 nvme_ctrl_get_trsvcid(c)) ||
	    (hostnqn && add_argument(argstr, "hostnqn", hostnqn)) ||
	    (hostid && add_argument(argstr, "hostid", hostid)) ||
	    add_int_argument(argstr, "nr_write_queues",
			     cfg->nr_write_queues, false) ||
	    add_int_argument(argstr, "nr_poll_queues",
			     cfg->nr_poll_queues, false) ||
	    add_int_argument(argstr, "reconnect_delay",
			     cfg->reconnect_delay, false) ||
	    (strcmp(transport, "loop") &&
	     add_int_argument(argstr, "ctrl_loss_tmo",
			      cfg->ctrl_loss_tmo, false)) ||
	    add_int_argument(argstr, "tos", cfg->tos, true) ||
	    add_bool_argument(argstr, "duplicate_connect",
			      cfg->duplicate_connect) ||
	    add_bool_argument(argstr, "disable_sqflow",
			      cfg->disable_sqflow) ||
	    (!strcmp(transport, "tcp") &&
	     add_bool_argument(argstr, "hdr_digest", cfg->hdr_digest)) ||
	    (!strcmp(transport, "tcp") &&
	     add_bool_argument(argstr, "data_digest", cfg->data_digest)) ||
	    add_int_argument(argstr, "queue_size", cfg->queue_size, false) ||
	    add_int_argument(argstr, "keep_alive_tmo",
			     cfg->keep_alive_tmo, false) ||
	    add_int_argument(argstr, "nr_io_queues",
			     cfg->nr_io_queues, false)) {
		free(*argstr);
		errno = ENOMEM;
		return -1;
	}

	return 0;
}

static int __nvmf_add_ctrl(const char *argstr)
{
	int ret, fd, len = strlen(argstr);
	char buf[0x1000], *options, *p;

	fd = open(nvmf_dev, O_RDWR);
	if (fd < 0) {
		nvme_msg(LOG_ERR, "Failed to open %s: %s\n",
			 nvmf_dev, strerror(errno));
		return -1;
	}

	nvme_msg(LOG_DEBUG, "add ctrl args '%s'\n", argstr);
	ret = write(fd, argstr, len);
	if (ret != len) {
		nvme_msg(LOG_NOTICE, "Failed to write to %s: %s\n",
			 nvmf_dev, strerror(errno));
		ret = -1;
		goto out_close;
	}

	len = read(fd, buf, sizeof(buf));
	if (len < 0) {
		nvme_msg(LOG_ERR, "Failed to read from %s: %s\n",
			 nvmf_dev, strerror(errno));
		ret = -1;
		goto out_close;
	}
	nvme_msg(LOG_DEBUG, "add ctrl response '%s'\n", buf);
	buf[len] = '\0';
	options = buf;
	while ((p = strsep(&options, ",\n")) != NULL) {
		if (!*p)
			continue;
		if (sscanf(p, "instance=%d", &ret) == 1)
			goto out_close;
	}

	nvme_msg(LOG_ERR, "Failed to parse ctrl info for \"%s\"\n", argstr);
	errno = EINVAL;
	ret = -1;
out_close:
	close(fd);
	return ret;
}

int nvmf_add_ctrl_opts(nvme_ctrl_t c, const struct nvme_fabrics_config *cfg)
{
	char *argstr;
	int ret;

	ret = build_options(c, &argstr, cfg);
	if (ret)
		return ret;

	ret = __nvmf_add_ctrl(argstr);
	free(argstr);
	return ret;
}

int nvmf_add_ctrl(nvme_host_t h, nvme_ctrl_t c,
		  const struct nvme_fabrics_config *cfg)
{
	char *argstr;
	int ret;

	ret = build_options(c, &argstr, cfg);
	if (ret)
		return ret;

	ret = __nvmf_add_ctrl(argstr);
	free(argstr);
	if (ret < 0)
		return ret;

	return nvme_init_ctrl(h, c, ret);
}

nvme_ctrl_t nvmf_connect_disc_entry(nvme_host_t h,
				    struct nvmf_disc_log_entry *e,
				    const struct nvme_fabrics_config *defcfg,
				    bool *discover)
{
	struct nvme_fabrics_config cfg = { 0 };
	const char *transport;
	char *traddr = NULL, *trsvcid = NULL;
	nvme_ctrl_t c;
	int ret;

	memcpy(&cfg, defcfg, sizeof(cfg));
	switch (e->subtype) {
	case NVME_NQN_DISC:
		if (discover)
			*discover = true;
		break;
	case NVME_NQN_NVME:
		break;
	default:
		nvme_msg(LOG_ERR, "skipping unsupported subtype %d\n",
			 e->subtype);
		errno = EINVAL;
		return NULL;
	}

	switch (e->trtype) {
	case NVMF_TRTYPE_RDMA:
	case NVMF_TRTYPE_TCP:
		switch (e->adrfam) {
		case NVMF_ADDR_FAMILY_IP4:
		case NVMF_ADDR_FAMILY_IP6:
			nvme_chomp(e->traddr, NVMF_TRADDR_SIZE);
			nvme_chomp(e->trsvcid, NVMF_TRSVCID_SIZE);
			traddr = e->traddr;
			trsvcid = e->trsvcid;
			break;
		default:
			nvme_msg(LOG_ERR, "skipping unsupported adrfam %d\n",
				 e->adrfam);
			errno = EINVAL;
			return NULL;
		}
		break;
        case NVMF_TRTYPE_FC:
		switch (e->adrfam) {
		case NVMF_ADDR_FAMILY_FC:
			nvme_chomp(e->traddr, NVMF_TRADDR_SIZE),
			traddr = e->traddr;
			trsvcid = NULL;
			break;
		default:
			nvme_msg(LOG_ERR, "skipping unsupported adrfam %d\n",
				 e->adrfam);
			errno = EINVAL;
			return NULL;
		}
	case NVMF_TRTYPE_LOOP:
		break;
	default:
		nvme_msg(LOG_ERR, "skipping unsupported transport %d\n",
			 e->trtype);
		errno = EINVAL;
		return NULL;
	}

	transport = nvmf_trtype_str(e->trtype);
	c = nvme_create_ctrl(e->subnqn, transport, traddr,
			     NULL, trsvcid);
	if (!c) {
		errno = ENOMEM;
		return NULL;
	}

	if (e->treq & NVMF_TREQ_DISABLE_SQFLOW)
		cfg.disable_sqflow = true;

	ret = nvmf_add_ctrl(h, c, &cfg);
	if (!ret)
		return c;

	if (errno == EINVAL && cfg.disable_sqflow) {
		errno = 0;
		/* disable_sqflow is unrecognized option on older kernels */
		cfg.disable_sqflow = false;
		ret = nvmf_add_ctrl(h, c, &cfg);
		if (!ret)
			return c;
	}
	nvme_free_ctrl(c);
	return NULL;
}

static int nvme_discovery_log(int fd, __u32 len, struct nvmf_discovery_log *log)
{
	return __nvme_get_log_page(fd, 0, NVME_LOG_LID_DISCOVER, true, 512,
				   len, log);
}

int nvmf_get_discovery_log(nvme_ctrl_t c, struct nvmf_discovery_log **logp,
			   int max_retries)
{
	struct nvmf_discovery_log *log;
	int hdr, ret, retries = 0;
	uint64_t genctr, numrec;
	unsigned int size;

	hdr = sizeof(struct nvmf_discovery_log);
	log = malloc(hdr);
	if (!log) {
		nvme_msg(LOG_ERR,
			 "could not allocate memory for discovery log header\n");
		errno = ENOMEM;
		return -1;
	}
	memset(log, 0, hdr);

	ret = nvme_discovery_log(nvme_ctrl_get_fd(c), 0x100, log);
	if (ret)
		goto out_free_log;

	do {
		numrec = le64_to_cpu(log->numrec);
		genctr = le64_to_cpu(log->genctr);

		if (numrec == 0) {
			*logp = log;
			return 0;
		}

		size = sizeof(struct nvmf_discovery_log) +
			sizeof(struct nvmf_disc_log_entry) * (numrec);

		free(log);
		log = malloc(size);
		if (!log) {
			nvme_msg(LOG_ERR,
				 "could not alloc memory for discovery log page\n");
			errno = ENOMEM;
			return -1;
		}
		memset(log, 0, size);

		ret = nvme_discovery_log(nvme_ctrl_get_fd(c), size, log);
		if (ret)
			goto out_free_log;

		genctr = le64_to_cpu(log->genctr);
		ret = nvme_discovery_log(nvme_ctrl_get_fd(c), hdr, log);
		if (ret)
			goto out_free_log;
	} while (genctr != le64_to_cpu(log->genctr) &&
		 ++retries < max_retries);

	if (genctr != le64_to_cpu(log->genctr)) {
		errno = EAGAIN;
		ret = -1;
	} else if (numrec != le64_to_cpu(log->numrec)) {
		errno = EBADSLT;
		ret = -1;
	} else {
		*logp = log;
		return 0;
	}

out_free_log:
	free(log);
	return ret;
}

#define PATH_DMI_ENTRIES       "/sys/firmware/dmi/entries"

int uuid_from_dmi(char *system_uuid)
{
	int f;
	DIR *d;
	struct dirent *de;
	char buf[512];

	system_uuid[0] = '\0';
	d = opendir(PATH_DMI_ENTRIES);
	if (!d)
		return -ENXIO;
	while ((de = readdir(d))) {
		char filename[PATH_MAX];
		int len, type;

		if (de->d_name[0] == '.')
			continue;
		sprintf(filename, "%s/%s/type", PATH_DMI_ENTRIES, de->d_name);
		f = open(filename, O_RDONLY);
		if (f < 0)
			continue;
		len = read(f, buf, 512);
		len = read(f, buf, 512);
		close(f);
		if (len < 0)
			continue;
		if (sscanf(buf, "%d", &type) != 1)
			continue;
		if (type != 1)
			continue;
		sprintf(filename, "%s/%s/raw", PATH_DMI_ENTRIES, de->d_name);
		f = open(filename, O_RDONLY);
		if (f < 0)
			continue;
		len = read(f, buf, 512);
		close(f);
		if (len < 0)
			continue;
		/* Sigh. https://en.wikipedia.org/wiki/Overengineering */
		/* DMTF SMBIOS 3.0 Section 7.2.1 System UUID */
		sprintf(system_uuid,
			"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-"
			"%02x%02x%02x%02x%02x%02x",
			(uint8_t)buf[8 + 3], (uint8_t)buf[8 + 2],
			(uint8_t)buf[8 + 1], (uint8_t)buf[8 + 0],
			(uint8_t)buf[8 + 5], (uint8_t)buf[8 + 4],
			(uint8_t)buf[8 + 7], (uint8_t)buf[8 + 6],
			(uint8_t)buf[8 + 8], (uint8_t)buf[8 + 9],
			(uint8_t)buf[8 + 10], (uint8_t)buf[8 + 11],
			(uint8_t)buf[8 + 12], (uint8_t)buf[8 + 13],
			(uint8_t)buf[8 + 14], (uint8_t)buf[8 + 15]);
		break;
	}
	closedir(d);
	return strlen(system_uuid) ? 0 : -ENXIO;
}

#ifdef CONFIG_SYSTEMD
#include <systemd/sd-id128.h>
#define NVME_HOSTNQN_ID SD_ID128_MAKE(c7,f4,61,81,12,be,49,32,8c,83,10,6f,9d,dd,d8,6b)
#endif

static int uuid_from_systemd(char *system_uuid)
{
	int ret = -ENOTSUP;
#ifdef CONFIG_SYSTEMD
	sd_id128_t id;

	ret = sd_id128_get_machine_app_specific(NVME_HOSTNQN_ID, &id);
	if (!ret)
		asprintf(systemd_uuid, SD_ID128_FORMAT_STR,
			 SD_ID128_FORMAT_VAL(id));
#endif
	return ret;
}

char *nvmf_hostnqn_generate()
{
	char *hostnqn;
	int ret;
	char uuid_str[37]; /* e.g. 1b4e28ba-2fa1-11d2-883f-0016d3cca427 + \0 */
#ifdef CONFIG_LIBUUID
	uuid_t uuid;
#endif

	ret = uuid_from_dmi(uuid_str);
	if (ret < 0)
		ret = uuid_from_systemd(uuid_str);
#ifdef CONFIG_LIBUUID
	if (ret < 0) {
		uuid_generate_random(uuid);
		uuid_unparse_lower(uuid, uuid_str);
		ret = 0;
	}
#endif
	if (ret < 0)
		return NULL;

	asprintf(&hostnqn, "nqn.2014-08.org.nvmexpress:uuid:%s\n", uuid_str);
	return hostnqn;
}

static char *nvmf_read_file(const char *f, int len)
{
	char buf[len];
	int ret, fd;

	fd = open(f, O_RDONLY);
	if (fd < 0)
		return false;

	memset(buf, 0, len);
	ret = read(fd, buf, len - 1);
	close (fd);

	if (ret < 0)
		return NULL;
	return strndup(buf, strcspn(buf, "\n"));
}

char *nvmf_hostnqn_from_file()
{
	return nvmf_read_file(nvmf_hostnqn_file, NVMF_NQN_SIZE);
}

char *nvmf_hostid_from_file()
{
	return nvmf_read_file(nvmf_hostid_file, NVMF_HOSTID_SIZE);
}
