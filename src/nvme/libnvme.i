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
  %immutable config_file;
  char *config_file;
};

struct nvme_host {
  %immutable hostnqn;
  %immutable hostid;
  char *hostnqn;
  char *hostid;
};

struct nvme_subsystem {
  %immutable subsysnqn;
  %immutable model;
  %immutable serial;
  %immutable firmware;
  char *subsysnqn;
  char *model;
  char *serial;
  char *firmware;
};

struct nvme_ctrl {
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
};

struct nvme_ns {
  %immutable nsid;
  %immutable eui64;
  %immutable nguid;
  %immutable uuid;
  unsigned int nsid;
  uint8_t eui64[8];
  uint8_t nguid[16];
  uint8_t uuid[16];
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
  %immutable name;
  const char *name;
}

%{
  const char *nvme_subsystem_name_get(struct nvme_subsystem *s) {
    return nvme_subsystem_get_name(s);
  }
%};

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
  nvme_ctrl(const char *subsysnqn, const char *transport,
	    const char *traddr, const char *host_traddr = NULL,
	    const char *trsvcid = NULL) {
    return nvme_create_ctrl(subsysnqn, transport, traddr, host_traddr, trsvcid);
  }
  ~nvme_ctrl() {
    nvme_free_ctrl($self);
  }
  void connect(struct nvme_host *h, int queue_size = 0,
	       int nr_io_queues = 0, int reconnect_delay = 0,
	       int ctrl_loss_tmo = 0, int keep_alive_tmo = 0,
	       int nr_write_queues = 0, int nr_poll_queues = 0,
	       int tos = 0, bool duplicate_connect = false,
	       bool disable_sqflow = false, bool hdr_digest = false,
	       bool data_digest = false, bool persistent = false) {
    int ret;
    const char *dev;
    struct nvme_fabrics_config cfg = {
      .queue_size = queue_size,
      .nr_io_queues = nr_io_queues,
      .reconnect_delay = reconnect_delay,
      .ctrl_loss_tmo = ctrl_loss_tmo,
      .keep_alive_tmo = keep_alive_tmo,
      .nr_write_queues = nr_write_queues,
      .nr_poll_queues = nr_poll_queues,
      .tos = tos, .duplicate_connect = duplicate_connect,
      .disable_sqflow = disable_sqflow,
      .hdr_digest = hdr_digest,
      .data_digest = data_digest,
    };

    dev = nvme_ctrl_get_name($self);
    if (dev && !duplicate_connect) {
      return;
    }
    ret = nvmf_add_ctrl(h, $self, &cfg, disable_sqflow);
    if (ret < 0) {
	return;
    }
  }
  void rescan() {
    nvme_rescan_ctrl($self);
  }
  void disconnect() {
    nvme_disconnect_ctrl($self);
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
  %immutable name;
  const char *name;
}

%{
  const char *nvme_ctrl_name_get(struct nvme_ctrl *c) {
    return nvme_ctrl_get_name(c);
  }
%};

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
  %immutable name;
  const char *name;
}

%{
  const char *nvme_ns_name_get(struct nvme_ns *n) {
    return nvme_ns_get_name(n);
  }
%};
