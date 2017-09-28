// Copyright (C) 2017 apertus° Association & contributors
//
// This file is part of Axiom Beta Rest Interface.
//
// Axiom Beta Rest Interface is free software:
// you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

package main

import (
	schema "Schema/AxiomDaemon"
	"fmt"
	"io"
	"log"
	"net"
	"strconv"

	flatbuffers "github.com/google/flatbuffers/go"
)

// Just a workaround, needs proper solution later
var c *Client

// Client for REST API
type Client struct {
	SocketPath string
	Builder    *flatbuffers.Builder
	Settings   []flatbuffers.UOffsetT
	Socket     net.Conn
}

// Init setups client
func (c *Client) Init() {
	c.SocketPath = "/tmp/axiom_daemon"
	c.SetupSocket()

	c.Builder = flatbuffers.NewBuilder(1024)
	c.Settings = make([]flatbuffers.UOffsetT, 0)
}

// reader processes the packages to send
func reader(r io.Reader) {
	buf := make([]byte, 1024)
	for {
		n, err := r.Read(buf[:])
		if err != nil {
			return
		}
		println("Client got:", string(buf[0:n]))
	}
}

// SetupSocket opens the socket connectiont to the daemon
func (c *Client) SetupSocket() {
	fmt.Printf("Socket path: %s\n", c.SocketPath)
	var err error
	c.Socket, err = net.Dial("unixgram", c.SocketPath)

	if err != nil {
		panic(err)
	}
}

// TransferData sends added settings to daemon
func (c *Client) TransferData() {
	//byteVector := c.Builder.CreateByteVector(c.Settings)

	schema.PacketStartSettingsVector(c.Builder, len(c.Settings))
	for _, element := range c.Settings {
		c.Builder.PrependUOffsetT(element)
	}
	settings := c.Builder.EndVector(len(c.Settings))

	schema.PacketStart(c.Builder)
	schema.PacketAddSettings(c.Builder, settings)
	p := schema.PacketEnd(c.Builder)
	c.Builder.Finish(p)

	bytes := c.Builder.FinishedBytes()

	_, err := c.Socket.Write(bytes)
	if err != nil {
		log.Fatal("write error:", err)
	}

	c.Settings = c.Settings[:0]
	c.Builder.Reset()
}

// AddSettingIS provides method to add image sensor settings
// Write/read setting of image sensor
// Fixed to 2 bytes for now, as CMV used 128 x 2 bytes registers and it should be sufficient for first tests
func (c *Client) AddSettingIS(mode schema.Mode, imageSensorSetting schema.ImageSensorSettings, parameter uint16) {
	schema.ImageSensorSettingStart(c.Builder)
	schema.ImageSensorSettingAddMode(c.Builder, mode)
	schema.ImageSensorSettingAddSetting(c.Builder, imageSensorSetting)
	schema.ImageSensorSettingAddParameter(c.Builder, parameter)
	is := schema.ImageSensorSettingEnd(c.Builder)

	schema.PayloadStart(c.Builder)
	schema.PayloadAddPayloadType(c.Builder, schema.SettingImageSensorSetting)
	schema.PayloadAddPayload(c.Builder, is)
	payload := schema.PayloadEnd(c.Builder)

	c.Settings = append(c.Settings, payload)
}

func ReceivedDataHandler(setting *Setting) {
	fmt.Printf("Setting received: %s\n", setting.ID)
	if setting.ID == "gain" {
		gainIndex, err := strconv.Atoi(setting.Value)
		if err != nil {
			fmt.Printf("Value cannot be converted\n")
			return
		}
		GainHandler(uint16(gainIndex))
	}
}

var gainValues [5]uint16
var adcRanges [5]uint16

func GainHandler(gainIndex uint16) {
	fmt.Printf("GainHandler()\n")

	gainValue := gainValues[gainIndex]
	adcRange := adcRanges[gainIndex]

	c.AddSettingIS(schema.ModeWrite, schema.ImageSensorSettingsGain, gainValue)
	c.AddSettingIS(schema.ModeWrite, schema.ImageSensorSettingsADCRange, adcRange)
	c.AddSettingIS(schema.ModeWrite, schema.ImageSensorSettingsADCRangeMult2, 1)
	c.AddSettingIS(schema.ModeWrite, schema.ImageSensorSettingsOffset1, 2000)
	c.AddSettingIS(schema.ModeWrite, schema.ImageSensorSettingsOffset2, 2000)

	c.TransferData()
}

func main() {
	gainValues = [...]uint16{0, 1, 3, 7, 11}
	adcRanges = [...]uint16{0x3eb, 0x3d5, 0x3d5, 0x3d5, 0x3e9}

	c = new(Client)
	c.Init()

	//c.AddSettingSPI(Mode::Write, )
	//c.AddSettingIS(schema.ModeWrite, schema.ImageSensorSettingsGain, 2)

	//c.TransferData()

	server := new(RESTserver)
	server.Init()
	server.AddReceivedDataHandler(ReceivedDataHandler)

	// TODO: Add c.Execute() to process sent settings as bulk
}
