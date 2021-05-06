// SPDX-License-Identifier: LGPL-2.1-or-later
/*
 * This file is part of libnvme.
 * Copyright (c) 2020 Western Digital Corporation or its affiliates.
 *
 * Authors: Keith Busch <keith.busch@wdc.com>
 * 	    Chaitanya Kulkarni <chaitanya.kulkarni@wdc.com>
 */

%module libnvme

%include "exception.i"

%allowexception;

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

struct nvme_host_iter {
    struct nvme_root *root;
    struct nvme_host *pos;
};

%}

#include "tree.h"
#include "fabrics.h"

struct nvme_root {
	bool modified;
};

struct nvme_host_iter {
    struct nvme_root *root;
    struct nvme_host *pos;
  };

struct nvme_host {
	char *hostnqn;
	char *hostid;
};

%extend nvme_root {
  nvme_root(const char *config_file = NULL) {
    return nvme_scan(config_file);
  }
  ~nvme_root() {
    nvme_free_tree($self);
  }
}

%extend nvme_host_iter {
  struct nvme_host_iter *__iter__() {
    return $self;
  }
    
  struct nvme_host *__next__() {
    struct nvme_host *this = $self->pos;

    if (!this) {
      PyErr_SetString(PyExc_StopIteration, "End of hosts");
      return NULL;
    }
    $self->pos = nvme_next_host($self->root, this);
    return this;
  }
}

%extend nvme_root {
  struct nvme_host_iter hosts() {
    struct nvme_host_iter ret = {$self, nvme_first_host($self)};
    return ret;
  }
}

%extend nvme_host {
  nvme_host(struct nvme_root *r, const char *hostnqn, const char *hostid) {
    return nvme_lookup_host(r, hostnqn, hostid);
  }
  ~nvme_host() {
    nvme_free_host($self);
  }
  char *__str__() {
    static char tmp[2048];

    sprintf(tmp, "nvme_host(%s,%s)", $self->hostnqn, $self->hostid);
    return tmp;
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

struct nvme_host *nvme_lookup_host(struct nvme_root *r,
				   const char *hostnqn = NULL,
				   const char *hostid = NULL);
struct nvme_subsystem *nvme_lookup_subsystem(struct nvme_host *h,
					     const char *name,
					     const char *subsysnqn);

struct nvme_ctrl *nvme_lookup_ctrl(struct nvme_subsystem *s,
				   const char *transport,
				   const char *traddr,
				   const char *host_traddr = NULL,
				   const char *trsvcid = NULL);

struct nvme_ctrl *nvme_create_ctrl(const char *subsysnqn,
				   const char *transport,
				   const char *traddr,
				   const char *host_traddr = NULL,
				   const char *trsvcid = NULL);

struct nvme_host *nvme_default_host(struct nvme_root *r);
struct nvme_root *nvme_scan(const char *config_file = NULL);
void nvme_free_tree(struct nvme_root *r);

void nvme_free_ctrl(struct nvme_ctrl *c);
int nvme_ctrl_disconnect(struct nvme_ctrl *c);
void nvme_unlink_ctrl(struct nvme_ctrl *c);
void nvme_refresh_topology(struct nvme_root *r);
void nvme_reset_topology(struct nvme_root *r);
int nvme_update_config(struct nvme_root *r, const char *config_file);
