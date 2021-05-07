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
#include <assert.h>
#include <ccan/list/list.h>
#include "tree.h"
#include "fabrics.h"

static int myErr = 0;

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

%inline %{
  struct nvme_host_iter {
    struct nvme_root *root;
    struct nvme_host *pos;
  };

  struct nvme_subsystem_iter {
    struct nvme_host *host;
    struct nvme_subsystem *pos;
  };

  struct nvme_ctrl_iter {
    struct nvme_subsystem *subsystem;
    struct nvme_ctrl *pos;
  };
%}

%exception nvme_host_iter::__next__ {
  assert(!myErr);
  $action
  if (myErr) {
    myErr = 0;
    PyErr_SetString(PyExc_StopIteration, "End of list");
    return NULL;
  }
}

%exception nvme_subsystem_iter::__next__ {
  assert(!myErr);
  $action
  if (myErr) {
    myErr = 0;
    PyErr_SetString(PyExc_StopIteration, "End of list");
    return NULL;
  }
}

%exception nvme_ctrl_iter::__next__ {
  assert(!myErr);
  $action
  if (myErr) {
    myErr = 0;
    PyErr_SetString(PyExc_StopIteration, "End of list");
    return NULL;
  }
}

#include "tree.h"
#include "fabrics.h"

struct nvme_root {
	bool modified;
};

struct nvme_host {
	char *hostnqn;
	char *hostid;
};

struct nvme_subsystem {
	struct nvme_host *host;

	char *name;
	char *sysfs_dir;
	char *subsysnqn;
	char *model;
	char *serial;
	char *firmware;
};

struct nvme_ctrl {
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

%extend nvme_root {
  nvme_root(const char *config_file = NULL) {
    return nvme_scan(config_file);
  }
  ~nvme_root() {
    nvme_free_tree($self);
  }
  struct nvme_host *hosts() {
    return nvme_first_host($self);
  }
}

%extend nvme_host_iter {
  struct nvme_host_iter *__iter__() {
    return $self;
  }
    
  struct nvme_host *__next__() {
    struct nvme_host *this = $self->pos;

    if (!this) {
      myErr = 1;
      return NULL;
    }
    $self->pos = nvme_next_host($self->root, this);
    return this;
  }
}

%extend nvme_host {
  nvme_host(struct nvme_root *r, const char *hostnqn,
	    const char *hostid = NULL) {
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
  struct nvme_host_iter __iter__() {
    struct nvme_host_iter ret = { .root = nvme_host_get_root($self),
				     .pos = $self };
    return ret;
  }
  struct nvme_subsystem *subsystems() {
    return nvme_first_subsystem($self);
  }
}

%extend nvme_subsystem_iter {
  struct nvme_subsystem_iter *__iter__() {
    return $self;
  }
  struct nvme_subsystem *__next__() {
    struct nvme_subsystem *this = $self->pos;

    if (!this) {
      myErr = 1;
      return NULL;
    }
    $self->pos = nvme_next_subsystem($self->host, this);
    return this;
  }
}

%extend nvme_subsystem {
  nvme_subsystem(struct nvme_host *host, const char *subsysnqn,
		 const char *name = NULL) {
    return nvme_lookup_subsystem(host, name, subsysnqn);
  }
  ~nvme_subsystem() {
    nvme_free_subsystem($self);
  }
  char *__str__() {
    static char tmp[1024];

    sprintf(tmp, "nvme_subsystem(%s,%s)", $self->name,$self->subsysnqn);
    return tmp;
  }
  struct nvme_subsystem_iter __iter__() {
    struct nvme_subsystem_iter ret = { .host = nvme_subsystem_get_host($self),
				       .pos = $self };
    return ret;
  }
  struct nvme_ctrl *ctrls() {
    return nvme_subsystem_first_ctrl($self);
  }
}
 
%extend nvme_ctrl_iter {
  struct nvme_ctrl_iter *__iter__() {
    return $self;
  }
  struct nvme_ctrl *__next__() {
    struct nvme_ctrl *this = $self->pos;
    
    if (!this) {
      myErr = 1;
      return NULL;
    }
    $self->pos = nvme_subsystem_next_ctrl($self->subsystem, this);
    return this;
  }
}

%extend nvme_ctrl {
  nvme_ctrl(struct nvme_subsystem *subsys, const char *transport,
	    const char *traddr, const char *host_traddr = NULL,
	    const char *trsvcid = NULL) {
    return nvme_lookup_ctrl(subsys, transport, traddr, host_traddr, trsvcid);
  }
  ~nvme_ctrl() {
    nvme_free_ctrl($self);
  }
  char *__str__() {
    static char tmp[1024];

    sprintf(tmp, "nvme_ctrl(%s,%s,%s,%s)", $self->transport, $self->traddr,
	    $self->host_traddr, $self->trsvcid);
    return tmp;
  }
  struct nvme_ctrl_iter __iter__() {
    struct nvme_ctrl_iter ret = { .subsystem = nvme_ctrl_get_subsystem($self),
				  .pos = $self };
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

struct nvme_host *nvme_default_host(struct nvme_root *r);
struct nvme_root *nvme_scan(const char *config_file = NULL);
void nvme_free_tree(struct nvme_root *r);

void nvme_free_ctrl(struct nvme_ctrl *c);
int nvme_ctrl_disconnect(struct nvme_ctrl *c);
void nvme_unlink_ctrl(struct nvme_ctrl *c);
void nvme_refresh_topology(struct nvme_root *r);
void nvme_reset_topology(struct nvme_root *r);
int nvme_update_config(struct nvme_root *r, const char *config_file);