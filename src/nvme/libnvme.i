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
#include "private.h"

static int host_iter_err = 0;
static int subsys_iter_err = 0;
static int ctrl_iter_err = 0;
static int ns_iter_err = 0;

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

  struct nvme_ns_iter {
    struct nvme_subsystem *subsystem;
    struct nvme_ctrl *ctrl;
    struct nvme_ns *pos;
  };
%}

%exception nvme_host_iter::__next__ {
  assert(!host_iter_err);
  $action
  if (host_iter_err) {
    host_iter_err = 0;
    PyErr_SetString(PyExc_StopIteration, "End of list");
    return NULL;
  }
}

%exception nvme_subsystem_iter::__next__ {
  assert(!subsys_iter_err);
  $action
  if (subsys_iter_err) {
    subsys_iter_err = 0;
    PyErr_SetString(PyExc_StopIteration, "End of list");
    return NULL;
  }
}

%exception nvme_ctrl_iter::__next__ {
  assert(!ctrl_iter_err);
  $action
  if (ctrl_iter_err) {
    ctrl_iter_err = 0;
    PyErr_SetString(PyExc_StopIteration, "End of list");
    return NULL;
  }
}

%exception nvme_ns_iter::__next__ {
  assert(!ns_iter_err);
  $action
  if (ns_iter_err) {
    ns_iter_err = 0;
    PyErr_SetString(PyExc_StopIteration, "End of list");
    return NULL;
  }
}

#include "tree.h"
#include "fabrics.h"

%typemap(out) uint8_t [8] {
  $result = PyBytes_FromStringAndSize((char *)$1, 8);
};

%typemap(out) uint8_t [16] {
  $result = PyBytes_FromStringAndSize((char *)$1, 16);
};

struct nvme_root {
  bool modified;
};

struct nvme_host {
  %immutable hostnqn;
  %immutable hostid;
  char *hostnqn;
  char *hostid;
};

struct nvme_subsystem {
  struct nvme_host *host;
  %immutable subsysnqn;
  %immutable name;
  char *subsysnqn;
  char *name;
  char *sysfs_dir;
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
  %immutable transport;
  %immutable subsysnqn;
  %immutable traddr;
  %immutable host_traddr;
  %immutable trsvcid;
  char *transport;
  char *subsysnqn;
  char *traddr;
  char *host_traddr;
  char *trsvcid;
  bool discovered;
  bool persistent;
  struct nvme_fabrics_config cfg;
};

struct nvme_ns {
	struct nvme_subsystem *subsystem;
	struct nvme_ctrl *ctrl;

	int fd;
  %immutable nsid;
  %immutable name;
	unsigned int nsid;
	char *name;
	char *sysfs_dir;

	int lba_shift;
	int lba_size;
	int meta_size;
	uint64_t lba_count;
	uint64_t lba_util;

  %immutable eui64;
  %immutable nguid;
  %immutable uuid;
	uint8_t eui64[8];
	uint8_t nguid[16];
	uint8_t uuid[16];
	enum nvme_csi csi;
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
  void refresh_topology() {
    nvme_refresh_topology($self);
  }
  void update_config() {
    nvme_update_config($self);
  }
}

%extend nvme_host_iter {
  struct nvme_host_iter *__iter__() {
    return $self;
  }
    
  struct nvme_host *__next__() {
    struct nvme_host *this = $self->pos;

    if (!this) {
      host_iter_err = 1;
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
      subsys_iter_err = 1;
      return NULL;
    }
    $self->pos = nvme_next_subsystem($self->host, this);
    return this;
  }
}

%extend nvme_ns_iter {
  struct nvme_ns_iter *__iter__() {
    return $self;
  }
  struct nvme_ns *__next__() {
    struct nvme_ns *this = $self->pos;

    if (!this) {
      ns_iter_err = 1;
      return NULL;
    }
    if ($self->ctrl)
      $self->pos = nvme_ctrl_next_ns($self->ctrl, this);
    else
      $self->pos = nvme_subsystem_next_ns($self->subsystem, this);
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
  struct nvme_ns *namespaces() {
    return nvme_subsystem_first_ns($self);
  }
}
 
%extend nvme_ctrl_iter {
  struct nvme_ctrl_iter *__iter__() {
    return $self;
  }
  struct nvme_ctrl *__next__() {
    struct nvme_ctrl *this = $self->pos;
    
    if (!this) {
      ctrl_iter_err = 1;
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
  struct nvme_ns *namespaces() {
    return nvme_ctrl_first_ns($self);
  }
}

%extend nvme_ns {
  nvme_ns(struct nvme_subsystem *s, unsigned int nsid) {
    return nvme_subsystem_lookup_namespace(s, nsid);
  }
  ~nvme_ns() {
    nvme_free_ns($self);
  }
  char *__str__() {
    static char tmp[1024];

    sprintf(tmp, "nvme_ns(%u)", $self->nsid);
    return tmp;
  }
  struct nvme_ns_iter __iter__() {
    struct nvme_ns_iter ret = { .ctrl = nvme_ns_get_ctrl($self),
				.subsystem = nvme_ns_get_subsystem($self),
				.pos = $self };
    return ret;
  }
}
