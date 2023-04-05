/**
 * IRKConfigurationMonitor.h
 */

#pragma once

#include "fdbclient/DatabaseConfiguration.h"
#include "fdbclient/NativeAPI.actor.h"
#include "flow/flow.h"

// Responsible for monitoring the throttling-relevant
// components of the database configuration
class IRKConfigurationMonitor {
public:
	virtual ~IRKConfigurationMonitor() = default;
	virtual bool areBlobGranulesEnabled() const = 0;
	virtual int getStorageTeamSize() const = 0;

	// Run actors to periodically refresh throttling-relevant statistics
	// Returned Future should never be ready, but can be used to propagate errors
	virtual Future<Void> run() = 0;
};

class RKConfigurationMonitor : public IRKConfigurationMonitor {
	friend class RKConfigurationMonitorImpl;
	Database db;
	DatabaseConfiguration configuration;

public:
	explicit RKConfigurationMonitor(Database db);
	~RKConfigurationMonitor();
	bool areBlobGranulesEnabled() const override;
	int getStorageTeamSize() const override;
	Future<Void> run() override;
};
