// SPDX-License-Identifier: LGPL-2.1-or-later
/*
 * This file is part of libnvme.
 * Copyright (c) 2020 Western Digital Corporation or its affiliates.
 *
 * Authors: Keith Busch <keith.busch@wdc.com>
 * 	    Chaitanya Kulkarni <chaitanya.kulkarni@wdc.com>
 */

%module libnvme
%{
#include <ccan/list/list.h>
#include "tree.h"
#include "fabrics.h"

struct nvme_ctrl {
	struct list_node entry;
	struct list_head paths;
	struct list_head namespaces;

	struct nvme_subsystem *subsystem;

	int fd;
	char *name;
	char *sysfs_dir;
	char *address;
	char *firmware;
	char *model;
	char *state;
	char *numa_node;
	char *queue_count;
	char *serial;
	char *sqsize;
	char *hostnqn;
	char *hostid;
	char *transport;
	char *subsysnqn;
	char *traddr;
	char *trsvcid;
	char *host_traddr;
	bool discovered;
	bool persistent;
	struct nvme_fabrics_config cfg;
};

struct nvme_subsystem {
	struct list_node entry;
	struct list_head ctrls;
	struct list_head namespaces;
	struct nvme_host *host;

	char *name;
	char *sysfs_dir;
	char *subsysnqn;
	char *model;
	char *serial;
	char *firmware;
};

struct nvme_host {
	struct list_node entry;
	struct list_head subsystems;
	struct nvme_root *root;

	char *hostnqn;
	char *hostid;
};

struct nvme_root {
	struct list_head hosts;
	bool modified;
};

%}

#include "tree.h"
#include "fabrics.h"

typedef struct nvme_root {
	bool modified;
} nvme_root_t;

%inline %{
  struct nvme_host_iter {
    nvme_host_t list;
    nvme_host_t pos;
  };
%}

typedef struct nvme_host {
	struct nvme_root *root;

	char *hostnqn;
	char *hostid;
} nvme_host_t;

%extend nvme_host_iter {
  struct nvme_host_iter *__iter__() {
    return $self;
  }
  nvme_host_t next() {
    if ($self->pos) {
      return nvme_next_host(nvme_host_get_root($self->list),
				   $self->pos);
    }
    return $self->list;
  }
}

%extend nvme_host {
  nvme_host(nvme_root_t r, const char *hostnqn, const char *hostid) {
    return nvme_lookup_host(r, hostnqn, hostid);
  }
  ~nvme_host() {
    nvme_free_host($self);
  }
  char *__str__() {
    static char tmp[1024];

    sprintf(tmp, "nvme_host(%s,%s)", $self->hostnqn, $self->hostid);
    return tmp;
  }
  struct nvme_host_iter __iter__() {
    struct nvme_host_iter ret = { $self, NULL };
    return ret;
  }
}

%inline %{
  struct nvme_subsystem_iter {
    nvme_subsystem_t list;
    nvme_subsystem_t pos;
  };
%}

typedef struct nvme_subsystem {
	struct nvme_host *host;

	char *name;
	char *sysfs_dir;
	char *subsysnqn;
	char *model;
	char *serial;
	char *firmware;
} nvme_subsystem_t;

%extend nvme_subsystem_iter {
  struct nvme_subsystem_iter *__iter__() {
    return $self;
  }
  nvme_subsystem_t next() {
    if ($self->pos) {
      return nvme_next_subsystem(nvme_subsystem_get_host($self->list),
				   $self->pos);
    }
    return $self->list;
  }
}

%extend nvme_subsystem {
  struct nvme_subsystem_iter __iter__() {
    struct nvme_subsystem_iter ret = { $self, NULL };
    return ret;
  }
}

%inline %{
struct nvme_ctrl_iter {
nvme_ctrl_t list;
nvme_ctrl_t pos;
};
%}

typedef struct nvme_ctrl {
	struct nvme_subsystem *subsystem;

	int fd;
	char *name;
	char *sysfs_dir;
	char *address;
	char *firmware;
	char *model;
	char *state;
	char *numa_node;
	char *queue_count;
	char *serial;
	char *sqsize;
	char *hostnqn;
	char *hostid;
	char *transport;
	char *subsysnqn;
	char *traddr;
	char *trsvcid;
	char *host_traddr;
	bool discovered;
	bool persistent;
	struct nvme_fabrics_config cfg;
} nvme_ctrl_t;

%extend nvme_ctrl_iter {
  struct nvme_ctrl_iter *__iter__() {
    return $self;
  }
  nvme_ctrl_t next() {
    if ($self->pos) {
      return nvme_subsystem_next_ctrl(nvme_ctrl_get_subsystem($self->list),
				      $self->pos);
    }
    return $self->list;
  }
}

%extend nvme_ctrl {
  struct nvme_ctrl_iter __iter__() {
    struct nvme_ctrl_iter ret = { $self, NULL };
    return ret;
  }
}

nvme_host_t nvme_lookup_host(nvme_root_t r, const char *hostnqn,
			     const char *hostid);
nvme_subsystem_t nvme_lookup_subsystem(struct nvme_host *h,
				       const char *name,
				       const char *subsysnqn);

nvme_ctrl_t nvme_lookup_ctrl(nvme_subsystem_t s, const char *transport,
			     const char *traddr, const char *host_traddr,
			     const char *trsvcid);

nvme_ctrl_t nvme_create_ctrl(const char *subsysnqn, const char *transport,
			     const char *traddr, const char *host_traddr,
			     const char *trsvcid);

void nvme_free_ns(struct nvme_ns *n);
int nvme_ns_read(nvme_ns_t n, void *buf, off_t offset, size_t count);
int nvme_ns_write(nvme_ns_t n, void *buf, off_t offset, size_t count);
int nvme_ns_verify(nvme_ns_t n, off_t offset, size_t count);
int nvme_ns_compare(nvme_ns_t n, void *buf, off_t offset, size_t count);
int nvme_ns_write_zeros(nvme_ns_t n, off_t offset, size_t count);
int nvme_ns_write_uncorrectable(nvme_ns_t n, off_t offset, size_t count);
int nvme_ns_flush(nvme_ns_t n);
int nvme_ns_identify(nvme_ns_t n, struct nvme_id_ns *ns);
int nvme_ns_identify_descs(nvme_ns_t n, struct nvme_ns_id_desc *descs);
int nvme_ctrl_identify(nvme_ctrl_t c, struct nvme_id_ctrl *id);
int nvme_ctrl_disconnect(nvme_ctrl_t c);
nvme_ctrl_t nvme_scan_ctrl(nvme_root_t r, const char *name);
int nvme_init_ctrl(nvme_host_t h, nvme_ctrl_t c, int instance);
void nvme_free_ctrl(struct nvme_ctrl *c);
void nvme_unlink_ctrl(struct nvme_ctrl *c);
nvme_root_t nvme_scan_filter(nvme_scan_filter_t f);
nvme_host_t nvme_default_host(nvme_root_t r);
nvme_root_t nvme_scan(const char *config_file);
void nvme_refresh_topology(nvme_root_t r);
void nvme_reset_topology(nvme_root_t r);
int nvme_update_config(nvme_root_t r, const char *config_file);
void nvme_free_tree(nvme_root_t r);
char *nvme_get_attr(const char *dir, const char *attr);
char *nvme_get_subsys_attr(nvme_subsystem_t s, const char *attr);
char *nvme_get_ctrl_attr(nvme_ctrl_t c, const char *attr);
char *nvme_get_ns_attr(nvme_ns_t n, const char *attr);
char *nvme_get_path_attr(nvme_path_t p, const char *attr);
nvme_ns_t nvme_scan_namespace(const char *name);
